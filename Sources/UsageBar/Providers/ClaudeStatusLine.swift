import Foundation
import UsageBarCore

/// Claude limits without touching Anthropic's usage endpoint.
///
/// Claude Code pipes a JSON blob into the user's status line command after every
/// reply, and for Pro/Max accounts that blob carries the same 5h and weekly
/// percentages the endpoint returns. The endpoint, meanwhile, puts third-party
/// pollers in a bucket that answers 429 for hours. So UsageBar installs a tiny
/// status line script that saves that JSON to disk, and reads it from there.
///
/// Opt-in from Settings, because it edits ~/.claude/settings.json. A status line
/// the user already had keeps running: the script pipes the same input to it.
enum ClaudeStatusLine {
    static let dir = home.appendingPathComponent(".claude/usagebar", isDirectory: true)
    static let snapshotURL = dir.appendingPathComponent("statusline.json")
    static let scriptURL = dir.appendingPathComponent("statusline.sh")
    static let previousCommandURL = dir.appendingPathComponent("previous-statusline-command")
    static let backupURL = dir.appendingPathComponent("settings.json.before-usagebar")
    static let settingsURL = home.appendingPathComponent(".claude/settings.json")

    private static let marker = ".claude/usagebar/statusline.sh"
    static var command: String { "sh \"\(scriptURL.path)\"" }

    /// Latest limits Claude Code reported, and when it reported them.
    static func read() -> (bars: [LimitBar], at: Date)? {
        guard let data = try? Data(contentsOf: snapshotURL),
              let at = fileMTime(snapshotURL) else { return nil }
        let bars = ClaudeLimits.parseStatusLine(data)
        return bars.isEmpty ? nil : (bars, at)
    }

    static var isInstalled: Bool {
        guard let settings = try? loadSettings(),
              let statusLine = settings["statusLine"] as? [String: Any],
              let cmd = statusLine["command"] as? String else { return false }
        return cmd.contains(marker)
    }

    // MARK: install / uninstall

    static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var settings = try loadSettings()

        // One pristine copy, taken the first time only, so repeated toggling can
        // never overwrite the user's original with an already-edited version.
        if fm.fileExists(atPath: settingsURL.path), !fm.fileExists(atPath: backupURL.path) {
            try? fm.copyItem(at: settingsURL.resolvingSymlinksInPath(), to: backupURL)
        }

        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        if let existing = statusLine["command"] as? String, !existing.contains(marker) {
            try existing.write(to: previousCommandURL, atomically: true, encoding: .utf8)
        }
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine
        try saveSettings(settings)
    }

    static func uninstall() throws {
        var settings = try loadSettings()
        guard var statusLine = settings["statusLine"] as? [String: Any],
              let cmd = statusLine["command"] as? String, cmd.contains(marker) else { return }
        let previous = (try? String(contentsOf: previousCommandURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let previous, !previous.isEmpty {
            statusLine["command"] = previous
            settings["statusLine"] = statusLine
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try saveSettings(settings)
        try? FileManager.default.removeItem(at: previousCommandURL)
    }

    // MARK: settings.json

    private static func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchFailure(message: "~/.claude/settings.json is not a JSON object")
        }
        return obj
    }

    private static func saveSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        // Through the symlink, if it is one: dotfile managers link this file, and an
        // atomic write would replace their link with a plain copy.
        try data.write(to: settingsURL.resolvingSymlinksInPath(), options: .atomic)
    }

    // MARK: the script

    /// POSIX sh plus macOS's own plutil, so it needs nothing installed. It saves
    /// only inputs that carry rate_limits: the first run of a session comes before
    /// any reply and has none, and must not wipe the last good numbers.
    static var script: String {
        #"""
        #!/bin/sh
        # Installed by UsageBar. Claude Code runs this after each reply; it saves the
        # rate limits for the UsageBar menu bar app. Remove it from Settings in UsageBar.
        dir="$HOME/.claude/usagebar"
        input=$(cat)
        case "$input" in
          *'"rate_limits"'*)
            printf '%s' "$input" > "$dir/statusline.json.tmp" && mv -f "$dir/statusline.json.tmp" "$dir/statusline.json"
            ;;
        esac
        prev="$dir/previous-statusline-command"
        if [ -s "$prev" ]; then
          printf '%s' "$input" | sh -c "$(cat "$prev")"
          exit
        fi
        pct() { printf '%s' "$input" | /usr/bin/plutil -extract "rate_limits.$1.used_percentage" raw -o - - 2>/dev/null; }
        five=$(pct five_hour)
        week=$(pct seven_day)
        line=""
        [ -n "$five" ] && line="5h $(printf '%.0f' "$five")%"
        [ -n "$week" ] && line="${line:+$line · }week $(printf '%.0f' "$week")%"
        printf '%s' "$line"
        """#
    }
}
