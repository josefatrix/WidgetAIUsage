import Foundation
import UsageBarCore

final class ClaudeProvider: UsageProvider {
    let id = ProviderID.claude
    private let fileCache = JSONLCache<[UsageEvent]>(persistKey: "claude-events")

    // Last good limits, reused when the endpoint fails or is throttled so bars never blank out.
    private var lastLimits: [LimitBar] = []
    private var lastExtraUsage: ExtraUsage? = nil
    private var lastLimitsFetch: Date? = nil
    private var limitsBackoffUntil: Date? = nil
    /// The usage endpoint rate-limits aggressively; refresh-on-open must not hammer it.
    private static let minLimitsInterval: TimeInterval = 60

    func fetch() async -> Result<ProviderSnapshot, FetchFailure> {
        let creds: ClaudeCredentials
        switch Self.readKeychainCredentials() {
        case .success(let c): creds = c
        case .failure(let f): return .failure(f)
        }
        let account = Self.readAccountEmail()
        let plan = creds.subscriptionType?.capitalized

        let (limits, extraUsage, limitsError) = await currentLimits(token: creds.accessToken)

        let sessionReset = limits.first { $0.label == "Session" }?.resetsAt
        let cost = scanCost(sessionResetsAt: sessionReset)

        if limits.isEmpty, let limitsError {
            // Degrade: local-only data if we have it, otherwise report the failure.
            if cost == nil { return .failure(FetchFailure(message: limitsError)) }
        }
        let history = historyCache
        return .success(ProviderSnapshot(account: account, plan: plan, limits: limits,
                                         cost: cost, history: history, fetchedAt: Date(),
                                         extraUsage: extraUsage, warning: limitsError))
    }

    /// Fresh limits when possible, otherwise the last good ones plus a message explaining why.
    private func currentLimits(token: String) async -> ([LimitBar], ExtraUsage?, String?) {
        let now = Date()
        if let until = limitsBackoffUntil, now < until {
            return (lastLimits, lastExtraUsage, Self.rateLimitedMessage(until: until, now: now))
        }
        if let last = lastLimitsFetch, !lastLimits.isEmpty,
           now.timeIntervalSince(last) < Self.minLimitsInterval {
            return (lastLimits, lastExtraUsage, nil)
        }
        do {
            let (limits, extra) = try await Self.fetchLimits(token: token)
            guard !limits.isEmpty else {
                return (lastLimits, lastExtraUsage, "Limits response had an unexpected format")
            }
            lastLimits = limits
            lastExtraUsage = extra
            lastLimitsFetch = now
            limitsBackoffUntil = nil
            return (limits, extra, nil)
        } catch let e as RateLimited {
            let until = now.addingTimeInterval(e.retryAfter)
            limitsBackoffUntil = until
            return (lastLimits, lastExtraUsage, Self.rateLimitedMessage(until: until, now: now))
        } catch {
            let message = (error as? FetchFailure)?.message ?? error.localizedDescription
            return (lastLimits, lastExtraUsage, message)
        }
    }

    private static func rateLimitedMessage(until: Date, now: Date) -> String {
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        return "Anthropic is rate-limiting usage checks. Retrying in \(minutes) min."
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
        // A pending Keychain permission prompt blocks `security` indefinitely. Waiting on it
        // used to wedge the whole refresh loop, so give up and report it instead.
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
                throw RateLimited(retryAfter: min(max(header, 60), 1800))
            }
            throw FetchFailure(message: "Limits endpoint returned \(http.statusCode)")
        }
        return (ClaudeLimits.parse(data), ClaudeLimits.parseExtraUsage(data))
    }

    // MARK: local cost scan

    private var historyCache: [DailyCost] = []

    private func scanCost(sessionResetsAt: Date?) -> CostSummary? {
        // Claude Code has used both locations; duplicates across them are removed by dedupe.
        let roots = [".claude/projects", ".config/claude/projects"].map { home.appendingPathComponent($0) }
        let cutoff = Date().addingTimeInterval(-31 * 24 * 3600)
        let files = roots.flatMap { jsonlFiles(under: $0, modifiedAfter: cutoff) }
        guard !files.isEmpty else { return nil }

        var events: [UsageEvent] = []
        for url in files {
            let parsed = fileCache.value(forFile: url) { contents in
                contents.split(separator: "\n").compactMap { ClaudeCost.parseLine(String($0)) }
            }
            if let parsed { events.append(contentsOf: parsed) }
        }
        events = Aggregation.dedupe(events)
        fileCache.save()
        guard !events.isEmpty else { return nil }

        let now = Date()
        let sessionStart = sessionResetsAt.map { $0.addingTimeInterval(-5 * 3600) } ?? now.addingTimeInterval(-5 * 3600)
        let session = Aggregation.sessionTotals(events: events, since: sessionStart)
        let history = Aggregation.dailyHistory(events: events, now: now, days: 30, calendar: .current)
        historyCache = history
        let total30 = history.reduce(0) { $0 + $1.costUSD }
        return CostSummary(sessionCostUSD: session.cost, sessionTokens: session.tokens,
                           last30DaysCostUSD: total30)
    }
}

private struct RateLimited: Error { let retryAfter: TimeInterval }
