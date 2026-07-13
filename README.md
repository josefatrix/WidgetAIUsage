# UsageBar

**A native macOS menu bar app that shows your Claude, Codex, and Gemini AI usage at a glance.**

Keep an eye on your AI subscription limits without leaving your workflow: session and weekly limit bars with reset countdowns, estimated cost and token counts, and a 30-day cost history chart, all from your menu bar.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Why?

If you use Claude Code, Codex, or Gemini CLI daily, you know the pain of hitting a rate limit mid-task. UsageBar reads the usage data these tools already store on your machine and turns it into a live, always-visible dashboard, so you can pace yourself before the limits do it for you.

## Features

- **Menu bar limit indicator** with configurable styles: bar, bar + percentage, or dual provider view
- **Session and weekly limit bars** with live reset countdowns
- **Estimated cost and token usage**, computed locally per model
- **30-day cost history chart** with date axis
- **Threshold notifications** at 80% and 95% of any limit
- **Severity colors** that match the API's own warning levels
- **Extra-usage credits** tracking (Claude)
- **Refresh on open** plus a persistent parse cache (`~/Library/Caches/UsageBar/`) for instant popovers
- **Launch at login** support

## Install

Requires **macOS 14+** and the Swift toolchain (Command Line Tools are enough, no Xcode needed).

```sh
git clone https://github.com/josefatrix/WidgetAIUsage.git
cd WidgetAIUsage
make test      # run the test suite
make install   # build release, bundle UsageBar.app, copy to /Applications, launch
```

On first launch macOS may ask for Keychain access to read the Claude Code credential ("security wants to use..."). Choose **Always Allow**.

## How it works

UsageBar never talks to any server on its own, with one exception: the Anthropic usage endpoint, called with the read-only token Claude Code already stores in your Keychain. Everything else comes from local files:

| Provider | Limits | Cost / tokens |
|---|---|---|
| **Claude** | Anthropic OAuth usage endpoint (token read from the `Claude Code-credentials` Keychain item) | `~/.claude/projects/**/*.jsonl` priced per model |
| **Codex** | `rate_limits` events in `~/.codex/sessions/**/*.jsonl` | Cumulative `total_token_usage` per session, priced by the session's model |
| **Gemini** | Not exposed locally (activity chart only) | User messages/day from `~/.gemini/tmp/*/logs.json` |

All access is **read-only**. Costs are estimates computed locally, not a bill.

## Project structure

```
Sources/
├── UsageBar/            # SwiftUI app: menu bar UI, popover, settings, notifications
│   ├── Providers/       # One isolated file per provider (Claude, Codex, Gemini)
│   └── UI/              # Limit bars, cost history chart, settings views
├── UsageBarCore/        # Pure logic: parsing, aggregation, pricing, Keychain
└── usagebar-tests/      # Test suite (run with `make test`)
```

## Debug

```sh
.build/debug/UsageBar --check
```

Prints both providers' live data to stdout and exits.

## Known limitations

- If the Claude access token is expired, limits show as stale until you use Claude Code again (the app never refreshes or rotates tokens on purpose).
- The Anthropic/OpenAI limit sources are undocumented and may change; each provider is isolated in a single file under `Sources/UsageBar/Providers/` to make fixes easy.
- "Launch at login" only works from the installed `/Applications/UsageBar.app`.

## License

[MIT](LICENSE)
