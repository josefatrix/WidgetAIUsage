import Foundation

public enum Codex {
    /// A general Codex quota observation, independent of the session/model that
    /// happened to report it. Persist the event date, never the file's mtime.
    public struct RateLimitObservation: Codable {
        public let limitID: String
        public let limitName: String?
        public let observedAt: Date
        public let limits: [LimitBar]
        public let plan: String?
    }

    /// Scan every event: appended records need not be in timestamp order, and
    /// a newer Spark event must not hide an earlier general Codex observation.
    public static func rateLimitObservation(in contents: String) -> RateLimitObservation? {
        var latest: RateLimitObservation?
        for line in contents.split(separator: "\n") where line.contains("rate_limits") {
            let text = String(line)
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestamp = ClaudeLimits.parseISODate(object["timestamp"] as? String),
                  let bars = findRateLimits(inLine: text),
                  let dictionary = generalRateLimitsDict(inLine: text) else { continue }
            if let latest, latest.observedAt >= timestamp { continue }
            latest = RateLimitObservation(limitID: dictionary["limit_id"] as? String ?? "codex",
                                          limitName: dictionary["limit_name"] as? String,
                                          observedAt: timestamp, limits: bars,
                                          plan: dictionary["plan_type"] as? String)
        }
        return latest
    }

    /// The caller can cache per-file parsing, but selection always uses the event
    /// timestamp and searches all files, not just the most recently touched five.
    public static func latestRateLimits(
        inFiles files: [URL],
        load: (URL) -> RateLimitObservation? = { url in
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return rateLimitObservation(in: contents)
        }
    ) -> RateLimitObservation? {
        files.compactMap(load).max { $0.observedAt < $1.observedAt }
    }

    public static func parseAuth(_ data: Data) -> (email: String?, plan: String?) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let jwt = tokens["id_token"] as? String else { return (nil, nil) }
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return (nil, nil) }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let payload = Data(base64Encoded: b64),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return (nil, nil) }
        let email = claims["email"] as? String
        let plan = (claims["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_plan_type"] as? String
        return (email, plan)
    }

    // Depth-first search for a dictionary under `key` anywhere in the JSON tree.
    static func findDict(_ key: String, in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if let hit = dict[key] as? [String: Any] { return hit }
            for v in dict.values { if let hit = findDict(key, in: v) { return hit } }
        } else if let arr = value as? [Any] {
            for v in arr { if let hit = findDict(key, in: v) { return hit } }
        }
        return nil
    }

    static func rateLimitsDict(inLine line: String) -> [String: Any]? {
        guard line.contains("rate_limits"), let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findDict("rate_limits", in: obj)
    }

    private static func generalRateLimitsDict(inLine line: String) -> [String: Any]? {
        guard let dictionary = rateLimitsDict(inLine: line) else { return nil }
        if let id = dictionary["limit_id"] as? String {
            guard id == "codex" else { return nil }
        } else if dictionary["limit_name"] as? String != nil {
            // Legacy unnamed events predate buckets; a named quota is scoped.
            return nil
        }
        return dictionary
    }

    /// Name a window by how long it actually is. The old code assumed `primary`
    /// was the 5h window and `secondary` the weekly one; since August 2026 Codex
    /// sends a single weekly window as `primary` with `secondary: null`, so any
    /// slot-based assumption mislabels it.
    public static func windowLabel(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "Limit" }
        switch minutes {
        case ...300: return "Session"
        case 1440: return "Daily"
        case 10_080: return "Weekly"
        default:
            if minutes % 10_080 == 0 { return "\(minutes / 10_080)-week" }
            if minutes % 1440 == 0 { return "\(minutes / 1440)-day" }
            return "\(minutes / 60)h"
        }
    }

    public static func findRateLimits(inLine line: String) -> [LimitBar]? {
        guard let rl = generalRateLimitsDict(inLine: line) else { return nil }
        var bars: [LimitBar] = []
        for slot in ["primary", "secondary"] {
            guard let w = rl[slot] as? [String: Any],
                  let pct = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let minutes = (w["window_minutes"] as? NSNumber)?.intValue
            var resets: Date? = nil
            if let epoch = (w["resets_at"] as? NSNumber)?.doubleValue { resets = Date(timeIntervalSince1970: epoch) }
            bars.append(LimitBar(label: windowLabel(minutes: minutes), percent: pct,
                                 resetsAt: resets, windowMinutes: minutes,
                                 kind: (minutes ?? 0) <= 300 ? .session : .overall))
        }
        guard !bars.isEmpty else { return nil }
        // Shortest window first — the tighter limit is the one that bites soonest.
        bars.sort { ($0.windowMinutes ?? .max) < ($1.windowMinutes ?? .max) }
        return bars
    }

    public static func planType(inLine line: String) -> String? {
        generalRateLimitsDict(inLine: line)?["plan_type"] as? String
    }

    /// First `"model":"…"` value in a session file (its primary model).
    public static func extractModel(from contents: String) -> String? {
        guard let r = contents.range(of: "\"model\":\"") else { return nil }
        let rest = contents[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let value = String(rest[..<end])
        return value.isEmpty ? nil : value
    }

    public static func findTotalTokenUsage(inLine line: String) -> (input: Int, cached: Int, output: Int)? {
        guard line.contains("total_token_usage"), let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let u = findDict("total_token_usage", in: obj) else { return nil }
        func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        return (n("input_tokens"), n("cached_input_tokens"), n("output_tokens"))
    }
}
