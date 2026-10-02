import Foundation

/// Which stretch of time the "cost so far" figure covers.
///
/// It used to be hardcoded as "the last 5 hours", found by looking for a limit
/// bar literally labelled "Session". That broke when OpenAI dropped the 5h
/// window from Codex's `rate_limits` (August 2026): no bar matched, so the
/// figure silently fell back to a 5h window with no data in it and always
/// showed $0. The window is now derived from whichever live limit is shortest,
/// whatever it happens to be called.
public enum UsageWindow {
    public static let fallbackSeconds = 5.0 * 3600

    /// Start of the shortest still-open limit window, plus the label the cost
    /// tile should carry. Expired windows are ignored — their start is in the
    /// past by a whole window and would sweep in unrelated usage.
    public static func current(limits: [LimitBar], now: Date,
                               fallback: TimeInterval = fallbackSeconds) -> (start: Date, label: String) {
        let live = limits.filter { !$0.hasExpired(now: now) }
        let shortest = live
            .compactMap { bar -> (Date, Int)? in
                guard let resets = bar.resetsAt, let minutes = bar.windowMinutes, minutes > 0
                else { return nil }
                return (resets, minutes)
            }
            .min { $0.1 < $1.1 }
        guard let (resets, minutes) = shortest else {
            return (now.addingTimeInterval(-fallback), tileLabel(minutes: nil))
        }
        return (resets.addingTimeInterval(-Double(minutes) * 60), tileLabel(minutes: minutes))
    }

    /// Every limit, most-used first — the order the dial and its legend read in.
    ///
    /// Ordering by window length seemed natural (5h outside, weekly inside) until
    /// Anthropic returned Session 1%, Weekly 62% and a per-model Fable bar at 100%
    /// on the same account: the window rule put 1% on the big ring and dropped the
    /// exhausted limit off the dial completely. What a person needs to see first is
    /// whatever is closest to biting, so that is what leads.
    ///
    /// Equal percentages fall back to the tighter window, so a tie does not shuffle
    /// between polls.
    public static func ranked(limits: [LimitBar], now: Date) -> [LimitBar] {
        limits.sorted {
            $0.percent == $1.percent
                ? ($0.windowMinutes ?? .max) < ($1.windowMinutes ?? .max)
                : $0.percent > $1.percent
        }
    }

    /// The two the dial draws, and they are FIXED: the current session window on
    /// the outer ring, the weekly one inside. Ranking them by pressure instead
    /// made the outer ring change meaning between polls, which defeats a dial —
    /// you should be able to read it without reading it.
    ///
    /// Per-model limits never take a ring (see `pressing`). Providers without a
    /// session window, like Codex today, put their longest window outside so the
    /// big ring is never the empty one.
    public static func rings(limits: [LimitBar], now: Date) -> (outer: LimitBar?, inner: LimitBar?) {
        let dialable = limits.filter { $0.kind != .scoped }
        let byWindow = dialable.sorted { ($0.windowMinutes ?? .max) < ($1.windowMinutes ?? .max) }
        let session = dialable.first { $0.kind == .session } ?? byWindow.first
        let overall = dialable.first { $0.kind == .overall && $0.id != session?.id }
            ?? byWindow.first { $0.id != session?.id }
        return (session, overall)
    }

    /// Threshold at which a limit the dial cannot draw still has to be said out loud.
    public static let pressingThreshold: Double = 85

    /// A per-model limit close to biting. It has no ring, so without this a model
    /// sitting at 100% would only ever be a quiet line in the legend.
    public static func pressing(limits: [LimitBar], now: Date) -> LimitBar? {
        ranked(limits: limits.filter { $0.kind == .scoped && $0.percent >= pressingThreshold },
               now: now).first
    }

    /// Tile heading matched to the window length, so the number is never labelled
    /// as something it isn't.
    public static func tileLabel(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "This session" }
        if minutes <= 300 { return "This session" }
        if minutes <= 1440 { return "Today" }
        if minutes <= 10_080 { return "This week" }
        return "This period"
    }
}
