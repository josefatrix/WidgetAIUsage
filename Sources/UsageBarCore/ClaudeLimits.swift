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

    public static func prettyModelName(_ id: String) -> String {
        for name in ["fable", "mythos", "opus", "sonnet", "haiku"] where id.contains(name) {
            return name.prefix(1).uppercased() + name.dropFirst()
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
                switch e.kind {
                case "session": label = "Session"
                case "weekly_all": label = "Weekly"
                case "weekly_scoped":
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
                                     resetsAt: parseISODate(e.resets_at), severity: e.severity))
            }
            if !bars.isEmpty { return bars }
        }
        var bars: [LimitBar] = []
        if let f = r.five_hour, let u = f.utilization {
            bars.append(LimitBar(label: "Session", percent: u, resetsAt: parseISODate(f.resets_at)))
        }
        if let s = r.seven_day, let u = s.utilization {
            bars.append(LimitBar(label: "Weekly", percent: u, resetsAt: parseISODate(s.resets_at)))
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
