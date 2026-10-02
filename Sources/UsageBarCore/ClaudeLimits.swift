import Foundation

public enum ClaudeLimits {
    struct Response: Decodable {
        struct Window: Decodable { let utilization: Double?; let resets_at: String? }
        struct Entry: Decodable {
            struct Scope: Decodable {
                struct M: Decodable { let id: String?; let display_name: String? }
                let model: M?
            }
            let kind: String?
            let percent: Double?
            let resets_at: String?
            let severity: String?
            let scope: Scope?
        }
        let five_hour: Window?
        let seven_day: Window?
        let limits: [Entry]?
    }

    public static func parseISODate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// "claude-opus-4-8" → "Opus". With `withVersion`, → "Opus 4.8".
    ///
    /// The bare family is what a limit bar's scope label wants; the cost breakdown
    /// needs the version, or two different models both render as "Opus" and the
    /// list shows the same name twice.
    public static func prettyModelName(_ id: String, withVersion: Bool = false) -> String {
        for name in ["fable", "mythos", "opus", "sonnet", "haiku"] where id.contains(name) {
            let family = name.prefix(1).uppercased() + name.dropFirst()
            guard withVersion, let range = id.range(of: name) else { return family }
            // Digit groups after the family name are the version; an 8-digit group
            // is a release date (claude-haiku-4-5-20251001), not part of it.
            let parts = id[range.upperBound...]
                .split(separator: "-")
                .prefix { $0.count < 8 && $0.allSatisfy(\.isNumber) }
            let version: [String] = parts.map { String($0) }
            guard !version.isEmpty else { return family }
            return family + " " + version.joined(separator: ".")
        }
        return id
    }

    public static func parse(_ data: Data) -> [LimitBar] {
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        if let entries = r.limits, !entries.isEmpty {
            var bars: [LimitBar] = []
            for e in entries {
                guard let pct = e.percent else { continue }
                let label: String
                let window: Int
                let kind: LimitKind
                switch e.kind {
                case "session": label = "Session"; window = 300; kind = .session
                case "weekly_all": label = "Weekly"; window = 10080; kind = .overall
                case "weekly_scoped":
                    window = 10080
                    kind = .scoped
                    if let display = e.scope?.model?.display_name {
                        label = display
                    } else if let id = e.scope?.model?.id {
                        label = prettyModelName(id)
                    } else {
                        label = "Model"
                    }
                default: continue
                }
                bars.append(LimitBar(label: label, percent: pct,
                                     resetsAt: parseISODate(e.resets_at), severity: e.severity,
                                     windowMinutes: window, kind: kind))
            }
            if !bars.isEmpty { return bars }
        }
        var bars: [LimitBar] = []
        if let f = r.five_hour, let u = f.utilization {
            bars.append(LimitBar(label: "Session", percent: u, resetsAt: parseISODate(f.resets_at),
                                 windowMinutes: 300, kind: .session))
        }
        if let s = r.seven_day, let u = s.utilization {
            bars.append(LimitBar(label: "Weekly", percent: u, resetsAt: parseISODate(s.resets_at),
                                 windowMinutes: 10080, kind: .overall))
        }
        return bars
    }

    /// The JSON Claude Code pipes into a status line command. After a reply it
    /// carries `rate_limits.five_hour` / `.seven_day`, each with `used_percentage`
    /// (0-100) and `resets_at` (epoch seconds); either window may be missing.
    /// Same labels and kinds as `parse`, so the two sources are interchangeable.
    public static func parseStatusLine(_ data: Data) -> [LimitBar] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = obj["rate_limits"] as? [String: Any] else { return [] }
        let windows: [(key: String, label: String, minutes: Int, kind: LimitKind)] = [
            ("five_hour", "Session", 300, .session),
            ("seven_day", "Weekly", 10080, .overall),
        ]
        var bars: [LimitBar] = []
        for w in windows {
            guard let entry = rl[w.key] as? [String: Any],
                  let pct = (entry["used_percentage"] as? NSNumber)?.doubleValue else { continue }
            let resets = (entry["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            bars.append(LimitBar(label: w.label, percent: pct, resetsAt: resets,
                                 windowMinutes: w.minutes, kind: w.kind))
        }
        return bars
    }

    public static func parseExtraUsage(_ data: Data) -> ExtraUsage? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let x = obj["extra_usage"] as? [String: Any] else { return nil }
        let enabled = x["is_enabled"] as? Bool ?? false
        let credits = (x["used_credits"] as? NSNumber)?.doubleValue ?? 0
        guard enabled || credits > 0 else { return nil }
        let decimals = (x["decimal_places"] as? NSNumber)?.intValue ?? 2
        let scale = pow(10.0, Double(decimals))
        let limit = (x["monthly_limit"] as? NSNumber)?.doubleValue ?? 0
        let utilization = (x["utilization"] as? NSNumber)?.doubleValue ?? 0
        return ExtraUsage(usedUSD: credits / scale, limitUSD: limit / scale, utilization: utilization)
    }
}
