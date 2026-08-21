import Foundation
import UsageBarCore

func testCodex() {
    // JWT: header.payload.sig with base64url payload
    let payload = #"{"email":"user@example.com","https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}"#
    let b64 = Data(payload.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    let auth = #"{"auth_mode":"chatgpt","tokens":{"id_token":"eyJh.\#(b64).sig"}}"#
    let acc = Codex.parseAuth(Data(auth.utf8))
    expectEq(acc.email, "user@example.com", "email")
    expectEq(acc.plan, "plus", "plan")

    let rlLine = #"{"timestamp":"x","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":6.0,"window_minutes":10080,"resets_at":1784523369},"secondary":{"used_percent":12.5,"window_minutes":300,"resets_at":1752429000},"plan_type":"plus"}}}"#
    guard let bars = Codex.findRateLimits(inLine: rlLine) else { expect(false, "rate limits nil"); return }
    expectEq(bars.count, 2, "two bars")
    // session (300 min) should sort first
    expectEq(bars[0].label, "Session", "session first")
    expectEq(bars[0].percent, 12.5, "session pct")
    expectEq(bars[1].label, "Weekly", "weekly second")
    expect(bars[1].resetsAt != nil, "weekly reset")
    expectEq(Codex.planType(inLine: rlLine), "plus", "plan type")
    expect(Codex.findRateLimits(inLine: #"{"a":1}"#) == nil, "no rate limits -> nil")

    let usageLine = #"{"payload":{"info":{"total_token_usage":{"input_tokens":7766351,"cached_input_tokens":7265280,"output_tokens":20770,"total_tokens":7787121}}}}"#
    guard let u = Codex.findTotalTokenUsage(inLine: usageLine) else { expect(false, "usage nil"); return }
    expectEq(u.input, 7766351, "cx input")
    expectEq(u.cached, 7265280, "cx cached")
    expectEq(u.output, 20770, "cx output")

    // model extraction (regression: split-count bug returned nil for real files)
    expectEq(Codex.extractModel(from: #"{"type":"session_meta","model":"gpt-5.1-codex-mini"}"#),
             "gpt-5.1-codex-mini", "extract codex model")
    expect(Codex.extractModel(from: #"{"no":"model here"}"#) == nil, "no model -> nil")

    // --- August 2026 format: OpenAI collapsed Codex to a single weekly window
    // (primary = 10080 min, secondary = null). The old <=300 heuristic still has
    // to label it correctly and must not choke on the null slot.
    let newFmt = #"{"payload":{"type":"token_count","rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":36.0,"window_minutes":10080,"resets_at":1785958439},"secondary":null,"credits":{"has_credits":false},"plan_type":"plus"}}}"#
    guard let nb = Codex.findRateLimits(inLine: newFmt) else { expect(false, "new-format rate limits nil"); return }
    expectEq(nb.count, 1, "new format → single bar")
    expectEq(nb[0].label, "Weekly", "new format weekly label")
    expectEq(nb[0].percent, 36.0, "new format pct")
    expectEq(nb[0].windowMinutes, 10080, "new format window")
    expectEq(Codex.planType(inLine: newFmt), "plus", "new format plan")

    // window labels are derived from the real window length, not assumed
    expectEq(Codex.windowLabel(minutes: 300), "Session", "300m → Session")
    expectEq(Codex.windowLabel(minutes: 1440), "Daily", "1440m → Daily")
    expectEq(Codex.windowLabel(minutes: 10080), "Weekly", "10080m → Weekly")
    expectEq(Codex.windowLabel(minutes: 720), "12h", "720m → 12h")
    expectEq(Codex.windowLabel(minutes: nil), "Limit", "unknown window → Limit")

    // bars sort shortest-window-first regardless of label
    let swapped = #"{"payload":{"rate_limits":{"primary":{"used_percent":36.0,"window_minutes":10080,"resets_at":1785958439},"secondary":{"used_percent":12.0,"window_minutes":300,"resets_at":1785958000}}}}"#
    guard let sb = Codex.findRateLimits(inLine: swapped) else { expect(false, "swapped nil"); return }
    expectEq(sb[0].windowMinutes, 300, "shortest window first")
    expectEq(sb[1].windowMinutes, 10080, "longest window last")
}
