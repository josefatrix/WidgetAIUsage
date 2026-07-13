import Foundation

public enum Codex {
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

    public static func findRateLimits(inLine line: String) -> [LimitBar]? {
        guard let rl = rateLimitsDict(inLine: line) else { return nil }
        var bars: [LimitBar] = []
        for slot in ["primary", "secondary"] {
            guard let w = rl[slot] as? [String: Any],
                  let pct = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let minutes = (w["window_minutes"] as? NSNumber)?.intValue
            let label = (minutes ?? 0) <= 300 ? "Session" : "Weekly"
            var resets: Date? = nil
            if let epoch = (w["resets_at"] as? NSNumber)?.doubleValue { resets = Date(timeIntervalSince1970: epoch) }
            bars.append(LimitBar(label: label, percent: pct, resetsAt: resets))
        }
        guard !bars.isEmpty else { return nil }
        bars.sort { ($0.label == "Session" ? 0 : 1) < ($1.label == "Session" ? 0 : 1) }
        return bars
    }

    public static func planType(inLine line: String) -> String? {
        rateLimitsDict(inLine: line)?["plan_type"] as? String
    }

    public static func findTotalTokenUsage(inLine line: String) -> (input: Int, cached: Int, output: Int)? {
        guard line.contains("total_token_usage"), let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let u = findDict("total_token_usage", in: obj) else { return nil }
        func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        return (n("input_tokens"), n("cached_input_tokens"), n("output_tokens"))
    }
}
