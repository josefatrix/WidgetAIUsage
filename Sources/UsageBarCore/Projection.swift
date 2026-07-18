import Foundation

/// Linear burn-rate projection: from the rate implied by how much of the window
/// has elapsed and how much has been used, estimate when 100% is reached.
/// Deliberately simple (a straight-line extrapolation) — labelled an estimate in the UI.
public enum Projection {
    static let minElapsedSeconds = 600.0  // need >10 min of window elapsed to trust the rate

    public static func forecast(percent: Double, resetsAt: Date, windowMinutes: Int, now: Date) -> Forecast? {
        guard percent > 0, percent < 100, windowMinutes > 0 else { return nil }
        let windowSeconds = Double(windowMinutes) * 60
        let windowStart = resetsAt.addingTimeInterval(-windowSeconds)
        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed > Self.minElapsedSeconds else { return nil }
        let ratePerSecond = percent / elapsed
        guard ratePerSecond > 0 else { return nil }
        let secondsToLimit = (100 - percent) / ratePerSecond
        let hitDate = now.addingTimeInterval(secondsToLimit)
        let secondsUntilReset = max(0, resetsAt.timeIntervalSince(now))
        let projected = percent + ratePerSecond * secondsUntilReset
        return Forecast(hitDate: hitDate,
                        willHitBeforeReset: hitDate < resetsAt,
                        projectedPercentAtReset: projected)
    }
}
