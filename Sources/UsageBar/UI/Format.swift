import Foundation

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
}
