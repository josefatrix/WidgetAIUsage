# UsageBar Improvements Plan (v1.1)

> Executed inline immediately after writing by the same agent with full context; interfaces are specified here, code detail lives in the diffs. User approved all 10 improvements ("aplica todo").

**Goal:** Apply the 10 approved improvements: refresh-on-open, live countdowns, chart date axis, API severity colors, threshold notifications, Codex model detection, persistent parse cache, menu bar display styles, Gemini tab, extra-usage credits.

## Task A — Core changes (TDD)
- `LimitBar` gains `severity: String?` (default nil; existing callers unaffected).
- `ClaudeLimits.parse` decodes `severity` per entry; new `ClaudeLimits.parseExtraUsage(Data) -> ExtraUsage?` reading `extra_usage {is_enabled, monthly_limit, used_credits, utilization, decimal_places}` → normalized `ExtraUsage { usedUSD, limitUSD, utilization }` (credits scaled by decimal_places); returns nil when absent/disabled-with-zero-use.
- `UsageEvent: Codable` (for persistent cache).
- `ProviderSnapshot` gains `extraUsage: ExtraUsage?` and `costUnit: CostUnit` (`.usd` default, `.requests` for Gemini).
- Tests: severity decode, extra usage decode (real fixture: used_credits 1859, decimal_places 2, monthly_limit 1000 → $18.59 / $10.00), UsageEvent round-trip.

## Task B — UI quick wins
- PopoverView `.onAppear` → silent `refreshAll()` (refresh when the popover opens).
- Wrap popover content in `TimelineView(.periodic(by: 30))`, pass `context.date` down so "Updated Xm ago" / "Resets in…" tick live (Format fns already take `now:`).
- CostHistoryView: date labels under the chart (first + last day).
- Bar colors: severity from API wins (`warning`→orange, `exceeded`/`critical`→red), threshold fallback (60/85%) when severity nil. Applies to LimitBarView and MenuBarLabel.
- "Extra usage" line in Claude tab when `extraUsage != nil`.

## Task C — Notifications, cache, Codex model, menu styles
- `Notifier` (app target): UNUserNotificationCenter, guarded by `Bundle.main.bundleIdentifier != nil` (bare dev binary has none). After each refresh, fire once per (provider, bar label, resetsAt window) when percent crosses 80 and again at 95; re-arms when resetsAt changes.
- `JSONLCache` becomes Codable-persistent: loads/saves `~/Library/Caches/UsageBar/<key>.json`, entries keyed path→(mtime, size, value). Cold starts stop re-parsing 31 days of JSONL.
- CodexProvider: read `"model":"…"` from session file (first match), price with it (fallback "gpt-5").
- Menu bar style setting: `bar` (actual), `percent` (bar + numeric %), `dual` (Claude+Codex stacked mini-bars). Picker in Settings, UserDefaults `menuBarStyle`.

## Task D — Gemini + release
- `GeminiProvider`: account from `~/.gemini/google_accounts.json` (`active`), daily request counts from `~/.gemini/tmp/*/logs.json` (`type=="user"` entries with ISO timestamp) → history with `costUnit: .requests`; no limits (informational note). Tab order Codex | Claude | Gemini.
- Popover/chart format respects `costUnit` (requests → "N requests" labels, no $).
- Bump CFBundleVersion to 1.1, `make install`, `--check` live verification, merge to main.
