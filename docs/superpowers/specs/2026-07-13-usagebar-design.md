# UsageBar — Design

**Date:** 2026-07-13
**Status:** Approved by user

## Purpose

A native macOS menu bar app (working name **UsageBar**), similar to CodexBar, that shows AI usage limits and cost for **Claude** and **Codex**. The user sees at a glance how much of their session and weekly limits they have used, estimated cost, and a 30-day cost history — without opening a terminal.

## Scope (v1)

In scope:

- Menu bar icon showing the active provider's session usage as a mini progress bar, with color shifting toward orange as usage nears the limit.
- Popover with a **Codex | Claude** tab switcher.
- Per provider: account/email, plan name, "Updated Xm ago".
- Progress bars: **Session** (5h window, with "Resets in Xh Ym"), **Weekly** (with "Resets in Xd Xh"), and per-model bar for Claude (Opus/Sonnet).
- **Cost** block: current session cost + token count, and last-30-days total.
- **Cost history (30 days)**: expandable floating panel with a daily bar chart (hover shows day, cost, tokens; total shown below).
- Actions: Refresh Now, Settings… (refresh interval, launch at login), Quit.

Out of scope (v1, YAGNI): Switch Account, Status Page link, web Usage Dashboard, Gemini support, threshold notifications. All can be added later; the provider abstraction leaves room for Gemini.

## Architecture

Native Swift/SwiftUI app using `MenuBarExtra`, built with Swift Package Manager (no full Xcode required), packaged into a `.app` by a build script. `LSUIElement = true` (no Dock icon). Three layers:

### 1. Providers

Common protocol `UsageProvider` with one implementation per provider. Each provider is the single place that knows its data sources, so upstream API changes are fixed in one file.

**ClaudeProvider**

- **Limits:** reads the OAuth credentials from the macOS Keychain (service `Claude Code-credentials`, verified present, includes `accessToken`, `refreshToken`, `expiresAt`, `subscriptionType`, `rateLimitTier`). Calls Anthropic's OAuth usage endpoint (the same one Claude Code's `/usage` uses) to get session %, weekly %, per-model % and reset timestamps. If the access token is expired, refreshes it with the `refreshToken` and writes the updated credentials back to the Keychain.
- **Cost/tokens:** parses session JSONL files under `~/.claude/projects/` (the same approach as ccusage): per-message token counts by model, priced with a per-model pricing table to estimate cost. Aggregates: current session (5h block), last 30 days by day.

**CodexProvider**

- **Limits:** reads tokens from `~/.codex/auth.json` (ChatGPT auth mode, verified present) and calls the ChatGPT backend rate-limits endpoint (as CodexBar does) for session/weekly percentages and resets.
- **Cost/tokens:** parses session logs under `~/.codex/sessions/` for token counts, priced with a per-model table.

Cost figures are **estimates** computed from local logs — not the provider's actual bill. The UI labels them as estimates.

### 2. Store

An observable `UsageStore` that:

- Polls both providers every N minutes (configurable, default 5) and on "Refresh Now".
- Keeps the last good snapshot per provider; a failed refresh never blanks the UI.
- Exposes per-provider state: `data + fetchedAt`, or `stale(lastGood, error)`.

### 3. UI

- **Menu bar item:** mini horizontal progress bar for the active provider's session usage.
- **Popover:** layout mirroring CodexBar's (tabs → header → three bars → cost block → cost-history row → actions). The cost-history row expands a floating panel with the 30-day daily bar chart.
- Visual polish (spacing, bar transitions, panel animation) follows the `emil-design-eng` skill guidance adapted to SwiftUI.

## Error handling

- Network/endpoint failure or expired token: tab shows the last good data with an "Updated Xm ago" stamp and a discreet warning; never crashes or blocks the menu bar.
- If a limits endpoint changes or breaks permanently, the app degrades to showing local-only data (cost/tokens), which needs no network.
- Missing data source (e.g., `~/.codex/auth.json` absent): that tab shows a "not connected" state; the other provider is unaffected.

## Known risk

The Anthropic and OpenAI limits endpoints are not documented public APIs — they are the same ones the CLIs and CodexBar use and may change without notice. Mitigation: isolated per-provider modules + local-data fallback.

## Build & distribution

- SwiftPM executable target; `make app` wraps it into `UsageBar.app` (Info.plist with `LSUIElement`) and copies it to `/Applications`.
- Ad-hoc code signing; personal use only — no App Store, no notarization.
- Optional launch-at-login via `SMAppService`.

## Testing

Unit tests for the real logic:

- Claude JSONL parser (anonymized real fixtures): token extraction per model, session blocking, cost math.
- Pricing table calculations.
- 30-day daily aggregation.
- Decoding of both limits endpoints' responses (recorded JSON fixtures), including error/expired-token shapes.

UI and polling verified manually by running the app; final acceptance is the app live in the user's menu bar showing real data for both tabs.
