import Foundation
import UsageBarCore

/// Parsed usage events for one Claude session file, tagged with its project.
struct ClaudeFileData: Codable {
    let events: [UsageEvent]
    let project: String?
}

final class ClaudeProvider: UsageProvider {
    let id = ProviderID.claude
    private let fileCache = JSONLCache<ClaudeFileData>(persistKey: "claude-files-v2")

    func fetch() async -> Result<ProviderSnapshot, FetchFailure> {
        let creds: ClaudeCredentials
        switch Self.readKeychainCredentials() {
        case .success(let c): creds = c
        case .failure(let f): return .failure(f)
        }
        let account = Self.readAccountEmail()
        let plan = creds.subscriptionType?.capitalized

        let now = Date()
        loadCachedLimits()

        var limits: [LimitBar] = []
        var extraUsage: ExtraUsage? = nil
        var limitsError: String? = nil
        var limitsNote: String? = nil
        do {
            if let until = limitsBackoffUntil, now < until {
                // Calling again while Anthropic is rate-limiting us only extends the
                // block; that is how a 429 used to stick around for a whole day.
                throw FetchFailure(message: Self.rateLimitedMessage(until: until, now: now))
            }
            if let expires = creds.expiresAt, expires < now {
                // Only the `claude` CLI renews this Keychain token. Someone who moved
                // to the desktop app's Code tab can be left with a dead one.
                throw FetchFailure(message: "Claude Code's saved sign-in expired \(Format.relativeAge(expires, now: now)). Run `claude` once in Terminal to renew it")
            }
            if let last = lastLimitsAt, !lastLimits.isEmpty,
               now.timeIntervalSince(last) < Self.minLimitsInterval {
                // Polls and popover opens arrive in bursts; one call a minute is plenty.
                limits = lastLimits
                extraUsage = lastExtra
            } else {
                (limits, extraUsage) = try await Self.fetchLimits(token: creds.accessToken)
                lastLimits = limits
                lastExtra = extraUsage
                lastLimitsAt = now
                limitsBackoffUntil = nil
                saveCachedLimits(limits, extra: extraUsage, at: now)
            }
        } catch {
            if let rate = error as? RateLimited {
                let until = now.addingTimeInterval(rate.retryAfter)
                limitsBackoffUntil = until
                limitsError = Self.rateLimitedMessage(until: until, now: now)
            } else {
                limitsError = (error as? FetchFailure)?.message ?? error.localizedDescription
            }
            // Rate limits and blips are routine: show the last good bars rather
            // than blanking the dial, flagged with how old they are and with any
            // window that has closed since marked stale. Cost still refreshes.
            if !lastLimits.isEmpty {
                limits = lastLimits.map { $0.hasExpired(now: now) ? $0.markedStale() : $0 }
                extraUsage = lastExtra
                limitsNote = lastLimitsAt.map {
                    "Limits from \(Format.relativeAge($0, now: now)) — \(limitsError ?? "the usage API is unavailable")."
                } ?? limitsError
                limitsError = nil
            } else {
                limitsNote = limitsError
            }
        }

        // Same window rule as every other provider: shortest live limit wins, and
        // the tile is labelled after whatever window that turned out to be.
        let cost = scanCost(window: UsageWindow.current(limits: limits, now: Date()))

        if limits.isEmpty, let limitsError {
            // Degrade: local-only data if we have it, otherwise report the failure.
            if cost == nil { return .failure(FetchFailure(message: limitsError)) }
        }
        return .success(ProviderSnapshot(account: account, plan: plan, limits: limits,
                                         cost: cost, history: historyCache, fetchedAt: now,
                                         limitsNote: limitsNote,
                                         extraUsage: extraUsage,
                                         modelBreakdown: modelBreakdownCache,
                                         projectBreakdown: projectBreakdownCache))
    }

    // MARK: keychain / account

    static func readKeychainCredentials() -> Result<ClaudeCredentials, FetchFailure> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch {
            return .failure(FetchFailure(message: "Couldn't run /usr/bin/security"))
        }
        // A pending Keychain permission prompt blocks `security` indefinitely, and
        // waiting on it used to wedge every later refresh. Give up and say why.
        if exited.wait(timeout: .now() + 30) == .timedOut {
            p.terminate()
            return .failure(FetchFailure(message: "Waiting for Keychain permission. Choose Always Allow on the prompt."))
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0, let creds = ClaudeCredentials.parse(data) else {
            return .failure(FetchFailure(message: "No Claude Code credentials in Keychain"))
        }
        return .success(creds)
    }

    static func readAccountEmail() -> String? {
        let url = home.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acc = obj["oauthAccount"] as? [String: Any] else { return nil }
        return acc["emailAddress"] as? String
    }

    // MARK: limits endpoint

    static func fetchLimits(token: String) async throws -> ([LimitBar], ExtraUsage?) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw FetchFailure(message: "No HTTP response") }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw FetchFailure(message: "Claude Code token expired. Run any claude command to renew it.")
            }
            if http.statusCode == 429 {
                let header = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) } ?? 300
                throw RateLimited(retryAfter: min(max(header, 120), 1800))
            }
            throw FetchFailure(message: "Limits endpoint returned \(http.statusCode)")
        }
        return (ClaudeLimits.parse(data), ClaudeLimits.parseExtraUsage(data))
    }

    // MARK: local cost scan

    private var historyCache: [DailyCost] = []
    private var modelBreakdownCache: [ModelCost] = []
    private var projectBreakdownCache: [ProjectCost] = []
    /// Last limits the API actually returned, kept on disk. Anthropic's usage
    /// endpoint 429s for long stretches, and a memory-only fallback is empty on
    /// every cold start — which is exactly when the dial went blank.
    struct CachedLimits: Codable {
        let bars: [LimitBar]
        let extra: ExtraUsage?
        let at: Date
    }

    private var lastLimits: [LimitBar] = []
    private var lastExtra: ExtraUsage? = nil
    private var lastLimitsAt: Date? = nil
    private var limitsBackoffUntil: Date? = nil
    /// The usage endpoint rate-limits aggressively; refresh-on-open must not hammer it.
    private static let minLimitsInterval: TimeInterval = 60

    private static func rateLimitedMessage(until: Date, now: Date) -> String {
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        return "Anthropic is rate-limiting usage checks; retrying in \(minutes) min"
    }

    private static var limitsCacheURL: URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let folder = dir.appendingPathComponent("UsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("claude-limits.json")
    }

    private func loadCachedLimits() {
        guard lastLimits.isEmpty, let url = Self.limitsCacheURL,
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedLimits.self, from: data) else { return }
        lastLimits = cached.bars
        lastExtra = cached.extra
        lastLimitsAt = cached.at
    }

    private func saveCachedLimits(_ bars: [LimitBar], extra: ExtraUsage?, at: Date) {
        guard let url = Self.limitsCacheURL,
              let data = try? JSONEncoder().encode(CachedLimits(bars: bars, extra: extra, at: at))
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func scanCost(window: (start: Date, label: String)) -> CostSummary? {
        // Claude Code has used both locations; duplicates across them are removed by dedupe.
        let roots = [".claude/projects", ".config/claude/projects"].map { home.appendingPathComponent($0) }
        let cutoff = Date().addingTimeInterval(-31 * 24 * 3600)
        let files = roots.flatMap { jsonlFiles(under: $0, modifiedAfter: cutoff) }
        guard !files.isEmpty else { return nil }

        var events: [UsageEvent] = []
        var projectCosts: [String: Double] = [:]
        for url in files {
            let data = fileCache.value(forFile: url) { contents -> ClaudeFileData in
                var parsed: [UsageEvent] = []
                var project: String? = nil
                for raw in contents.split(separator: "\n") {
                    let line = String(raw)
                    if let e = ClaudeCost.parseLine(line) { parsed.append(e) }
                    if project == nil, line.contains("\"cwd\""),
                       let d = line.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                       let cwd = obj["cwd"] as? String {
                        project = Aggregation.lastPathComponent(cwd)
                    }
                }
                if project == nil {
                    let decoded = url.deletingLastPathComponent().lastPathComponent
                        .replacingOccurrences(of: "-", with: "/")
                    project = Aggregation.lastPathComponent(decoded)
                }
                return ClaudeFileData(events: Aggregation.dedupe(parsed), project: project)
            }
            guard let data else { continue }
            events.append(contentsOf: data.events)
            if let project = data.project {
                projectCosts[project, default: 0] += data.events.reduce(0) { $0 + $1.costUSD }
            }
        }
        events = Aggregation.dedupe(events)
        fileCache.save()
        guard !events.isEmpty else { return nil }

        let now = Date()
        let cutoff30 = now.addingTimeInterval(-30 * 24 * 3600)
        let session = Aggregation.sessionTotals(events: events, since: window.start)
        historyCache = Aggregation.dailyHistory(events: events, now: now, days: 30, calendar: .current)
        modelBreakdownCache = Aggregation.modelBreakdown(events: events, since: cutoff30)
        projectBreakdownCache = Aggregation.topProjects(projectCosts, limit: 8)
        let total30 = historyCache.reduce(0) { $0 + $1.costUSD }
        return CostSummary(sessionCostUSD: session.cost, sessionTokens: session.tokens,
                           last30DaysCostUSD: total30, sessionLabel: window.label)
    }
}

private struct RateLimited: Error { let retryAfter: TimeInterval }
