import Foundation
import UsageBarCore

func testMenuBarMetrics() {
    let usable = 30.0
    // 0% draws nothing
    expectEq(MenuBarMetrics.fillWidth(percent: 0, usableWidth: usable), 0.0, "zero -> no fill")
    // any nonzero percent is visible (>= 2px)
    expect(MenuBarMetrics.fillWidth(percent: 1, usableWidth: usable) >= 2, "1% visible")
    // strictly monotonic across the range (the original bug: 5%..25% looked identical)
    var prev = -1.0
    for pct in stride(from: 2.0, through: 100, by: 2) {
        let w = MenuBarMetrics.fillWidth(percent: pct, usableWidth: usable)
        expect(w > prev, "monotonic at \(pct)% (\(w) <= \(prev))")
        prev = w
    }
    // 7% vs 24% must be clearly distinguishable (>= 3px apart)
    let low = MenuBarMetrics.fillWidth(percent: 7, usableWidth: usable)
    let mid = MenuBarMetrics.fillWidth(percent: 24, usableWidth: usable)
    expect(mid - low >= 3, "7% vs 24% distinguishable (\(low) vs \(mid))")
    // clamped at 100%
    expectEq(MenuBarMetrics.fillWidth(percent: 150, usableWidth: usable), usable, "clamped")
}
