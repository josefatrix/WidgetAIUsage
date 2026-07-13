import Foundation
import UsageBarCore

func testClaudeLimits() {
    let json = """
    {"five_hour":{"utilization":16.0,"resets_at":"2026-07-13T19:29:59.893458+00:00"},
     "seven_day":{"utilization":21.0,"resets_at":"2026-07-18T09:59:59.893487+00:00"},
     "limits":[
      {"kind":"session","group":"session","percent":16,"severity":"normal","resets_at":"2026-07-13T19:29:59.893458+00:00","scope":null,"is_active":false},
      {"kind":"weekly_all","group":"weekly","percent":21,"severity":"normal","resets_at":"2026-07-18T09:59:59.893487+00:00","scope":null,"is_active":false},
      {"kind":"weekly_scoped","group":"weekly","percent":38,"severity":"normal","resets_at":"2026-07-18T09:59:59.893828+00:00","scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":false}]}
    """.data(using: .utf8)!
    let bars = ClaudeLimits.parse(json)
    expectEq(bars.count, 3, "bar count")
    if bars.count == 3 {
        expectEq(bars[0].label, "Session", "session label")
        expectEq(bars[0].percent, 16.0, "session pct")
        expect(bars[0].resetsAt != nil, "session reset parsed")
        expectEq(bars[1].label, "Weekly", "weekly label")
        expectEq(bars[2].label, "Fable", "scoped label")
        expectEq(bars[2].percent, 38.0, "scoped pct")
    }

    // fallback path: no limits array
    let fallback = """
    {"five_hour":{"utilization":5.0,"resets_at":"2026-07-13T19:29:59+00:00"},
     "seven_day":{"utilization":9.0,"resets_at":null}}
    """.data(using: .utf8)!
    let fb = ClaudeLimits.parse(fallback)
    expectEq(fb.count, 2, "fallback count")
    if fb.count == 2 {
        expectEq(fb[0].label, "Session", "fallback session")
        expectEq(fb[1].percent, 9.0, "fallback weekly pct")
    }

    expectEq(ClaudeLimits.prettyModelName("claude-sonnet-4-6"), "Sonnet", "pretty sonnet")
    expectEq(ClaudeLimits.prettyModelName("claude-opus-4-8"), "Opus", "pretty opus")

    // severity decoded from limits entries
    expectEq(bars.first?.severity, "normal", "severity decoded")
}

func testExtraUsage() {
    let json = """
    {"limits":[],"extra_usage":{"is_enabled":false,"monthly_limit":1000,"used_credits":1859.0,"utilization":100.0,"currency":"USD","decimal_places":2}}
    """.data(using: .utf8)!
    guard let x = ClaudeLimits.parseExtraUsage(json) else { expect(false, "extra usage nil"); return }
    expect(abs(x.usedUSD - 18.59) < 1e-9, "used \(x.usedUSD)")
    expect(abs(x.limitUSD - 10.0) < 1e-9, "limit \(x.limitUSD)")
    expectEq(x.utilization, 100.0, "utilization")

    // absent → nil; enabled-but-unused → nil
    expect(ClaudeLimits.parseExtraUsage(Data("{}".utf8)) == nil, "absent -> nil")
    let unused = #"{"extra_usage":{"is_enabled":false,"monthly_limit":1000,"used_credits":0,"utilization":0,"decimal_places":2}}"#
    expect(ClaudeLimits.parseExtraUsage(Data(unused.utf8)) == nil, "zero+disabled -> nil")
}
