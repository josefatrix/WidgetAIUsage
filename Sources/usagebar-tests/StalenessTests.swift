import Foundation
import UsageBarCore

/// Regression suite for the August 2026 Codex breakage: OpenAI dropped the 5h
/// window from `rate_limits` (primary is now the weekly one, secondary null) and
/// local rollouts can go weeks without a new file — so the app was presenting a
/// long-expired snapshot as if it were current.
func testStaleness() {
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2026-08-20T20:00:00Z")!

    func bar(_ label: String, _ pct: Double, resets: Date?, window: Int?) -> LimitBar {
        LimitBar(label: label, percent: pct, resetsAt: resets, windowMinutes: window)
    }

    // --- a limit whose window already closed is not current data ---
    let expired = bar("Weekly", 36, resets: now.addingTimeInterval(-15 * 86_400), window: 10_080)
    expect(expired.hasExpired(now: now), "reset in the past → expired")
    expect(!bar("Weekly", 36, resets: now.addingTimeInterval(3600), window: 10_080).hasExpired(now: now),
           "future reset → live")
    expect(!bar("Weekly", 36, resets: nil, window: 10_080).hasExpired(now: now),
           "no reset date → not treated as expired")

    // marking keeps the number but flags it so the UI can grey it out
    let marked = expired.markedStale()
    expectEq(marked.severity, "stale", "stale severity")
    expectEq(marked.percent, 36.0, "stale keeps percent")
    expectEq(marked.label, "Weekly", "stale keeps label")

    // --- cost window comes from the shortest LIVE limit, not a label match ---
    let weeklyOnly = [bar("Weekly", 36, resets: now.addingTimeInterval(2 * 86_400), window: 10_080)]
    let w1 = UsageWindow.current(limits: weeklyOnly, now: now)
    expectEq(w1.start, now.addingTimeInterval(2 * 86_400 - 10_080 * 60), "weekly window start")
    expectEq(w1.label, "This week", "weekly tile label")

    let both = [bar("Session", 12, resets: now.addingTimeInterval(3600), window: 300),
                bar("Weekly", 36, resets: now.addingTimeInterval(2 * 86_400), window: 10_080)]
    let w2 = UsageWindow.current(limits: both, now: now)
    expectEq(w2.start, now.addingTimeInterval(3600 - 300 * 60), "shortest live window wins")
    expectEq(w2.label, "This session", "session tile label")

    // expired windows are ignored → 5h fallback
    let w3 = UsageWindow.current(limits: [expired], now: now)
    expectEq(w3.start, now.addingTimeInterval(-5 * 3600), "expired → 5h fallback")
    expectEq(w3.label, "This session", "fallback tile label")
    expectEq(UsageWindow.current(limits: [], now: now).start, now.addingTimeInterval(-5 * 3600),
             "no limits → 5h fallback")

    // --- snapshot reports the age of the DATA, not of the fetch ---
    let old = now.addingTimeInterval(-20 * 86_400)
    let scraped = ProviderSnapshot(account: nil, plan: nil, limits: [], cost: nil,
                                   history: [], fetchedAt: now, dataThrough: old)
    expectEq(scraped.asOf, old, "asOf prefers dataThrough")
    expect(scraped.isStale(now: now, threshold: 6 * 3600), "20d-old data is stale")

    let live = ProviderSnapshot(account: nil, plan: nil, limits: [], cost: nil,
                                history: [], fetchedAt: now)
    expectEq(live.asOf, now, "asOf falls back to fetchedAt")
    expect(!live.isStale(now: now, threshold: 6 * 3600), "just-fetched data is fresh")
}

/// ChatGPT keeps no quota on disk — only one opaque `.data` file per conversation
/// under a per-account `conversations-v3-<uuid>` folder. All this layer has to get
/// right is which folders and files count.
func testChatGPTActivity() {
    let dirs = [
        "conversations-v3-5f305855-87d9-40ae-9ce1-8a3bf293024a",
        "conversations-v3-aaaa1111-bbbb-2222-cccc-333344445555",
        "drafts-v2-5f305855-87d9-40ae-9ce1-8a3bf293024a",
        "codex-taskItems-v2-default-5f305855",
        "io.sentry",
        "conversations-v2-old"
    ]
    let found = ChatGPTActivity.conversationDirs(in: dirs).sorted()
    expectEq(found.count, 2, "two account folders")
    expect(found.allSatisfy { $0.hasPrefix("conversations-v3-") }, "only v3 conversation folders")
    expect(!found.contains("conversations-v2-old"), "v2 is a different layout, not counted")
    expectEq(ChatGPTActivity.conversationDirs(in: []).count, 0, "no folders -> none")

    expect(ChatGPTActivity.isConversationFile("0B323FD2-D9E8-40C2-B356-92D1B5CB3E8D.data"), "a .data file counts")
    expect(!ChatGPTActivity.isConversationFile("index.json"), "json is not a conversation")
    expect(!ChatGPTActivity.isConversationFile(".DS_Store"), "dotfile is not a conversation")
}

/// The concentric dial needs two rings: the tightest window outside, the next
/// distinct one inside. Claude can report several 7-day bars (one per model
/// scope), and those must not fight over the inner ring.
func testDialRings() {
    let now = Date()
    func bar(_ label: String, _ pct: Double, _ mins: Int) -> LimitBar {
        LimitBar(label: label, percent: pct, resetsAt: now.addingTimeInterval(3600),
                 windowMinutes: mins, kind: mins <= 300 ? .session : .overall)
    }
    func scoped(_ label: String, _ pct: Double) -> LimitBar {
        LimitBar(label: label, percent: pct, resetsAt: now.addingTimeInterval(3600),
                 windowMinutes: 10_080, kind: .scoped)
    }

    // The real shape Anthropic returns: a 5h window, an all-model weekly one, and
    // a per-model weekly one. Ordering by WINDOW put Session (1%) on the outer ring
    // and hid a model sitting at 100% entirely — the one number that mattered.
    let claude = UsageWindow.ranked(limits: [bar("Session", 1, 300),
                                             bar("Weekly", 62, 10_080),
                                             bar("Fable", 100, 10_080)], now: now)
    expectEq(claude.count, 3, "every limit is kept")
    expectEq(claude[0].label, "Fable", "the limit closest to biting leads the legend")
    expectEq(claude[1].label, "Weekly", "then the next highest")
    expectEq(claude[2].label, "Session", "the roomiest last")

    // The rings themselves are FIXED, not ranked: current session outside, weekly
    // inside, every time. A dial whose outer ring changes meaning between polls
    // cannot be read at a glance, which is the whole point of a dial.
    let rings = UsageWindow.rings(limits: [scoped("Fable", 100),
                                           bar("Weekly", 62, 10_080),
                                           bar("Session", 1, 300)], now: now)
    expectEq(rings.outer?.label, "Session", "outer ring is always the session window")
    expectEq(rings.inner?.label, "Weekly", "inner ring is always the weekly window")

    // Per-model limits never take a ring — they live in the legend, and get their
    // own warning when they are the thing about to bite.
    expectEq(UsageWindow.pressing(limits: [scoped("Fable", 100),
                                           bar("Weekly", 62, 10_080),
                                           bar("Session", 1, 300)], now: now)?.label,
             "Fable", "a scoped limit at 100% is surfaced separately")
    expect(UsageWindow.pressing(limits: [scoped("Fable", 40),
                                         bar("Session", 1, 300)], now: now) == nil,
           "a roomy scoped limit needs no warning")

    // Codex today: one weekly window and nothing else — inner ring stays empty.
    let codex = UsageWindow.rings(limits: [bar("Weekly", 36, 10_080)], now: now)
    expectEq(codex.outer?.label, "Weekly", "with no session window the weekly one takes the outer ring")
    expect(codex.inner == nil, "no second limit -> no inner ring")

    let none = UsageWindow.rings(limits: [], now: now)
    expect(none.outer == nil && none.inner == nil, "no limits -> no rings")

    // a bar with no window length can still be the only thing we have
    let unknown = UsageWindow.rings(limits: [LimitBar(label: "Limit", percent: 20, resetsAt: nil)], now: now)
    expectEq(unknown.outer?.label, "Limit", "windowless bar still shows")

    // ties keep a stable order rather than shuffling between polls
    let tied = UsageWindow.ranked(limits: [bar("B", 50, 10_080), bar("A", 50, 300)], now: now)
    expectEq(tied[0].label, "A", "equal percentages fall back to the tighter window")
}

/// Limit bars have to survive a restart on disk: Anthropic's usage endpoint can
/// 429 for long stretches, and a cold start with no cache is what leaves the dial
/// reading "NO LIMIT DATA" when we do know the last good figures.
func testLimitBarCoding() {
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2026-08-20T20:00:00Z")!
    let bars = [
        LimitBar(label: "Session", percent: 62, resetsAt: now.addingTimeInterval(3600),
                 severity: "warning", windowMinutes: 300),
        LimitBar(label: "Weekly", percent: 41, resetsAt: nil, severity: nil, windowMinutes: 10_080)
    ]
    guard let data = try? JSONEncoder().encode(bars),
          let back = try? JSONDecoder().decode([LimitBar].self, from: data) else {
        expect(false, "limit bars round-trip"); return
    }
    expectEq(back, bars, "bars survive encode/decode")

    let extra = ExtraUsage(usedUSD: 12.5, limitUSD: 40, utilization: 31.25)
    guard let ed = try? JSONEncoder().encode(extra),
          let eback = try? JSONDecoder().decode(ExtraUsage.self, from: ed) else {
        expect(false, "extra usage round-trip"); return
    }
    expectEq(eback, extra, "extra usage survives encode/decode")

    // Rehydrated bars whose window has since closed must come back flagged.
    let later = now.addingTimeInterval(2 * 3600)
    let rehydrated = back.map { $0.hasExpired(now: later) ? $0.markedStale() : $0 }
    expectEq(rehydrated[0].severity, "stale", "expired session bar flagged on reload")
    expectEq(rehydrated[1].severity, nil, "bar with no reset date left alone")
}

/// The colour has to track consumption. Anthropic reports severity "normal" well
/// past 60%, and taking the API's word for it meant a bar at 65% stayed the same
/// calm blue as one at 5% — the meter's colour said nothing at all.
func testLimitLevel() {
    // thresholds apply when the API is relaxed about it
    expectEq(LimitLevel.of(percent: 5, severity: "normal"), .normal, "5% is normal")
    expectEq(LimitLevel.of(percent: 65, severity: "normal"), .warning, "65% warns despite 'normal'")
    expectEq(LimitLevel.of(percent: 92, severity: "normal"), .critical, "92% is critical despite 'normal'")

    // and the API wins when IT is the more alarmed of the two
    expectEq(LimitLevel.of(percent: 12, severity: "critical"), .critical, "API critical at 12% still critical")
    expectEq(LimitLevel.of(percent: 12, severity: "warning"), .warning, "API warning at 12% still warns")
    expectEq(LimitLevel.of(percent: 100, severity: "warning"), .critical, "100% outranks an API warning")

    // no severity at all → pure thresholds (Codex never sends one)
    expectEq(LimitLevel.of(percent: 36, severity: nil), .normal, "36% with no severity")
    expectEq(LimitLevel.of(percent: 60, severity: nil), .warning, "60% is the warning edge")
    expectEq(LimitLevel.of(percent: 85, severity: nil), .critical, "85% is the critical edge")

    // stale is a state, not a severity, and outranks everything
    expectEq(LimitLevel.of(percent: 99, severity: "stale"), .stale, "stale wins over any percentage")
}
