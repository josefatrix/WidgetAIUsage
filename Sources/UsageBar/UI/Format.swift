import Foundation
import UsageBarCore

enum Format {
    static func relativeAge(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 90 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        return "\(s / 86_400)d ago"
    }

    static func resetsIn(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "Resets in \(d)d \(h)h" }
        if h > 0 { return "Resets in \(h)h \(m)m" }
        return "Resets in \(m)m"
    }

    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.0fM tokens", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fK tokens", Double(n) / 1_000)
        default: return "\(n) tokens"
        }
    }

    static func usd(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }

    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// Bare "1d 8h" / "2h 5m" / "12m" — no "Resets in" prefix.
    static func etaShort(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// Compact model name for breakdowns: Claude → "Opus"/"Fable"; gpt/codex trimmed.
    static func shortModel(_ model: String) -> String {
        if model.hasPrefix("claude-") { return UsageBarCore.ClaudeLimits.prettyModelName(model) }
        if model.hasPrefix("gpt-") || model.hasPrefix("codex-") {
            return model.replacingOccurrences(of: "-codex", with: "")
        }
        return model
    }
}
