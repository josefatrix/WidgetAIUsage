import Foundation

/// Pure geometry for the menu bar fill so it stays testable.
/// Original bug: a 3px floor + full capsule caps on a 22px-wide track made
/// every value between 0% and ~25% render as the same dot.
public enum MenuBarMetrics {
    public static let minVisible = 2.0

    /// Linear fill width: 0 at 0%, clamped to usable, never below `minVisible`
    /// for nonzero percents but still strictly increasing with percent.
    public static func fillWidth(percent: Double, usableWidth: Double) -> Double {
        let frac = max(0, min(1, percent / 100))
        guard frac > 0 else { return 0 }
        // Map 0..100% onto minVisible..usableWidth so tiny values stay visible
        // without flattening growth anywhere in the range.
        return minVisible + (usableWidth - minVisible) * frac
    }
}
