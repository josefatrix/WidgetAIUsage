import Foundation
import UsageBarCore

final class ClaudeProvider: UsageProvider {
    let id = ProviderID.claude
    private let fileCache = JSONLCache<[UsageEvent]>(persistKey: "claude-events")

    func fetch() async -> Result<ProviderSnapshot, FetchFailure> {
        guard let creds = Self.readKeychainCredentials() else {
            return .failure(FetchFailure(message: "No Claude Code credentials in Keychain"))
        }
        let account = Self.readAccountEmail()
        let plan = creds.subscriptionType?.capitalized

        var limits: [LimitBar] = []
        var extraUsage: ExtraUsage? = nil
        var limitsError: String? = nil
        do {
            (limits, extraUsage) = try await Self.fetchLimits(token: creds.accessToken)
        } catch {
            limitsError = (error as? FetchFailure)?.message ?? error.localizedDescription
        }

        let sessionReset = limits.first { $0.label == "Session" }?.resetsAt
        let cost = scanCost(sessionResetsAt: sessionReset)

        if limits.isEmpty, let limitsError {
            // Degrade: local-only data if we have it, otherwise report the failure.
            if cost == nil { return .failure(FetchFailure(message: limitsError)) }
        }
        let history = historyCache
        return .success(ProviderSnapshot(account: account, plan: plan, limits: limits,
                                         cost: cost, history: history, fetchedAt: Date(),
                                         extraUsage: extraUsage))
    }

    // MARK: keychain / account

    static func readKeychainCredentials() -> ClaudeCredentials? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return ClaudeCredentials.parse(data)
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
                throw FetchFailure(message: "Token expired — open Claude Code to refresh")
            }
            throw FetchFailure(message: "Limits endpoint returned \(http.statusCode)")
        }
        return (ClaudeLimits.parse(data), ClaudeLimits.parseExtraUsage(data))
    }

    // MARK: local cost scan

    private var historyCache: [DailyCost] = []

    private func scanCost(sessionResetsAt: Date?) -> CostSummary? {
        let root = home.appendingPathComponent(".claude/projects")
        let cutoff = Date().addingTimeInterval(-31 * 24 * 3600)
        let files = jsonlFiles(under: root, modifiedAfter: cutoff)
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
