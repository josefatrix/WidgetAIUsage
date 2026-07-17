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
}
