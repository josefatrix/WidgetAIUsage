# UsageBar

Native macOS menu bar app (à la CodexBar) showing **Claude** and **Codex** usage:
session/weekly limit bars with reset times, estimated cost + tokens, and a
30-day cost history chart.

## Build & install

```sh
make test      # run the test suite
make install   # build release, bundle UsageBar.app, copy to /Applications, launch
```

Requires macOS 14+ and the Swift toolchain (Command Line Tools are enough — no Xcode needed).

On first launch macOS may ask for Keychain access to read the Claude Code
credential ("security wants to use..."), choose **Always Allow**.

## Data sources

| Provider | Limits | Cost/tokens |
|---|---|---|
| Claude | Anthropic OAuth usage endpoint (token read-only from the `Claude Code-credentials` Keychain item) | `~/.claude/projects/**/*.jsonl` priced per model |
| Codex | `rate_limits` events in `~/.codex/sessions/**/*.jsonl` | cumulative `total_token_usage` per session, priced by the session's model |
| Gemini | not exposed locally (activity chart only) | user messages/day from `~/.gemini/tmp/*/logs.json` |

All access is **read-only**. Costs are estimates computed locally — not a bill.

v1.1: refresh on popover open, live countdowns, threshold notifications (80%/95%),
API severity colors, extra-usage credits, chart date axis, persistent parse cache
(`~/Library/Caches/UsageBar/`), menu bar icon styles (bar / bar+% / dual), Gemini tab.

## Debug

`.build/debug/UsageBar --check` prints both providers' live data to stdout and exits.

## Known limitations

- If the Claude access token is expired, limits show as stale until you use
  Claude Code again (the app never refreshes/rotates tokens on purpose).
- The Anthropic/OpenAI limit sources are undocumented and may change; each
  provider is isolated in one file (`Sources/UsageBar/Providers/`).
- "Launch at login" only works from the installed `/Applications/UsageBar.app`.
