import Foundation
import UsageBarCore

func testClaudeCost() {
    let line = #"{"type":"assistant","timestamp":"2026-07-13T17:43:54.307Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-opus-4-8","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":400,"output_tokens":50}}}"#
    guard let e = ClaudeCost.parseLine(line) else { expect(false, "parseLine returned nil"); return }
    expectEq(e.model, "claude-opus-4-8", "model")
    expectEq(e.input, 100, "input"); expectEq(e.output, 50, "output")
    expectEq(e.cacheWrite, 200, "cacheWrite"); expectEq(e.cacheRead, 400, "cacheRead")
    expectEq(e.dedupeKey, "msg_1:req_1", "dedupe key")
    // cost = 100/1M*5 + 50/1M*25 + 200/1M*6.25 + 400/1M*0.5
    expect(abs(e.costUSD - 0.0032) < 1e-9, "cost \(e.costUSD)")

    expect(ClaudeCost.parseLine(#"{"type":"user","message":{}}"#) == nil, "non-assistant skipped")
    expect(ClaudeCost.parseLine("not json") == nil, "garbage skipped")
    let synth = #"{"type":"assistant","timestamp":"2026-07-13T17:43:54.307Z","message":{"model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}"#
    expect(ClaudeCost.parseLine(synth) == nil, "synthetic skipped")
}

func testAggregation() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2026-07-13T18:00:00Z")!
    func ev(_ ts: String, cost: Double, tokens: Int, key: String? = nil) -> UsageEvent {
        UsageEvent(timestamp: iso.date(from: ts)!, model: "claude-opus-4-8",
                   input: tokens, output: 0, cacheWrite: 0, cacheRead: 0,
                   dedupeKey: key, costUSD: cost)
    }
    let events = [
        ev("2026-07-13T17:00:00Z", cost: 1.0, tokens: 10),
        ev("2026-07-13T10:00:00Z", cost: 2.0, tokens: 20),
        ev("2026-07-12T10:00:00Z", cost: 4.0, tokens: 40),
        ev("2026-06-01T10:00:00Z", cost: 8.0, tokens: 80),  // outside 30d window
    ]
    let hist = Aggregation.dailyHistory(events: events, now: now, days: 30, calendar: cal)
    expectEq(hist.count, 30, "30 days")
    expectEq(hist[29].costUSD, 3.0, "today cost")
    expectEq(hist[28].costUSD, 4.0, "yesterday cost")
    expectEq(hist[0].costUSD, 0.0, "old day zero-filled")

    let sess = Aggregation.sessionTotals(events: events, since: iso.date(from: "2026-07-13T15:00:00Z")!)
    expectEq(sess.cost, 1.0, "session cost")
    expectEq(sess.tokens, 10, "session tokens")

    let dup = [ev("2026-07-13T17:00:00Z", cost: 1, tokens: 1, key: "a:b"),
               ev("2026-07-13T17:00:00Z", cost: 1, tokens: 1, key: "a:b"),
               ev("2026-07-13T17:00:00Z", cost: 1, tokens: 1, key: nil)]
    expectEq(Aggregation.dedupe(dup).count, 2, "dedupe by key")
}
