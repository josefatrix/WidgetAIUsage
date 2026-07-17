import Foundation
import UsageBarCore

func testProjection() {
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2026-07-13T18:00:00Z")!

    // 30% with 3h elapsed (5h window resets in 2h) → 10%/h → 7h to limit → survives reset
    let f1 = Projection.forecast(percent: 30, resetsAt: now.addingTimeInterval(2 * 3600),
                                 windowMinutes: 300, now: now)!
    expect(!f1.willHitBeforeReset, "30% slow → survives")

    // 85% with 4h elapsed (resets in 1h) → 21.25%/h → ~42m to limit → hits before reset
    let f2 = Projection.forecast(percent: 85, resetsAt: now.addingTimeInterval(3600),
                                 windowMinutes: 300, now: now)!
    expect(f2.willHitBeforeReset, "85% fast → hits before reset")
    expect(f2.hitDate < now.addingTimeInterval(3600), "hit before reset date")

    // insufficient data (<10min elapsed) → nil
    let early = Projection.forecast(percent: 5, resetsAt: now.addingTimeInterval(300 * 60 - 300),
                                    windowMinutes: 300, now: now)
    expect(early == nil, "insufficient data → nil")

    // degenerate percents → nil
    expect(Projection.forecast(percent: 0, resetsAt: now.addingTimeInterval(3600), windowMinutes: 300, now: now) == nil, "0% → nil")
    expect(Projection.forecast(percent: 100, resetsAt: now.addingTimeInterval(3600), windowMinutes: 300, now: now) == nil, "100% → nil")
}

func testModelBreakdown() {
    let iso = ISO8601DateFormatter()
    let since = iso.date(from: "2026-07-01T00:00:00Z")!
    func ev(_ model: String, _ cost: Double, _ tok: Int, _ ts: String) -> UsageEvent {
        UsageEvent(timestamp: iso.date(from: ts)!, model: model, input: tok, output: 0,
                   cacheWrite: 0, cacheRead: 0, dedupeKey: nil, costUSD: cost)
    }
    let events = [
        ev("claude-opus-4-8", 5, 10, "2026-07-10T00:00:00Z"),
        ev("claude-opus-4-8", 3, 20, "2026-07-11T00:00:00Z"),
        ev("claude-fable-5", 9, 5, "2026-07-12T00:00:00Z"),
        ev("claude-sonnet-5", 1, 100, "2026-06-01T00:00:00Z"), // before `since` → excluded
    ]
    let b = Aggregation.modelBreakdown(events: events, since: since)
    expectEq(b.count, 2, "two models in window")
    expectEq(b[0].model, "claude-fable-5", "fable top by cost")
    expectEq(b[0].costUSD, 9.0, "fable cost")
    expectEq(b[1].model, "claude-opus-4-8", "opus second")
    expectEq(b[1].costUSD, 8.0, "opus summed")
    expectEq(b[1].tokens, 30, "opus tokens summed")
}

func testProjects() {
    expectEq(Aggregation.lastPathComponent("/Users/joseescorcia/usageModels"), "usageModels", "cwd basename")
    expectEq(Aggregation.lastPathComponent("/Users/jose/my-project/"), "my-project", "trailing slash")
    expectEq(Aggregation.lastPathComponent("plain"), "plain", "no slash")

    let top = Aggregation.topProjects(["a": 10, "b": 3, "c": 20, "d": 1], limit: 2)
    expectEq(top.count, 2, "top 2")
    expectEq(top[0].project, "c", "highest first")
    expectEq(top[0].costUSD, 20.0, "c cost")
    expectEq(top[1].project, "a", "second highest")
}
