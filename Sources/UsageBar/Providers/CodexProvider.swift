import Foundation
import UsageBarCore

final class CodexProvider: UsageProvider {
    let id = ProviderID.codex
    // Per session file: last cumulative token usage (input, cached, output).
    private let usageCache = JSONLCache<[Int]>()

    func fetch() async -> Result<ProviderSnapshot, FetchFailure> {
        let sessionsRoot = home.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: sessionsRoot.path) else {
            return .failure(FetchFailure(message: "Codex not set up (~/.codex/sessions missing)"))
        }
        let authData = try? Data(contentsOf: home.appendingPathComponent(".codex/auth.json"))
        let account: (email: String?, plan: String?) =
            authData.flatMap { Codex.parseAuth($0) } ?? (email: nil, plan: nil)

        let cutoff = Date().addingTimeInterval(-31 * 24 * 3600)
        let files = jsonlFiles(under: sessionsRoot, modifiedAfter: cutoff)
            .sorted { (fileMTime($0) ?? .distantPast) > (fileMTime($1) ?? .distantPast) }

        // Limits: newest rate_limits event across the most recent files.
        var limits: [LimitBar] = []
        var plan: String? = account.plan
        for url in files.prefix(5) {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n").reversed() {
                if let bars = Codex.findRateLimits(inLine: String(line)) {
                    limits = bars
                    plan = Codex.planType(inLine: String(line)) ?? plan
                    break
                }
            }
            if !limits.isEmpty { break }
        }

        // Cost: last cumulative total_token_usage per session file, priced as gpt-5.
        var events: [UsageEvent] = []
        for url in files {
            let totals = usageCache.value(forFile: url) { contents in
                for line in contents.split(separator: "\n").reversed() {
                    if let u = Codex.findTotalTokenUsage(inLine: String(line)) {
                        return [u.input, u.cached, u.output]
                    }
                }
                return []
            }
            guard let totals, totals.count == 3, let mtime = fileMTime(url) else { continue }
            let (input, cached, output) = (totals[0], totals[1], totals[2])
            let uncached = max(0, input - cached)
            let cost = Pricing.costUSD(model: "gpt-5", input: uncached, output: output,
                                       cacheWrite: 0, cacheRead: cached)
            events.append(UsageEvent(timestamp: mtime, model: "gpt-5",
                                     input: input, output: output, cacheWrite: 0, cacheRead: cached,
                                     dedupeKey: nil, costUSD: cost))
        }

        var cost: CostSummary? = nil
        var history: [DailyCost] = []
        if !events.isEmpty {
            let now = Date()
            let sessionReset = limits.first { $0.label == "Session" }?.resetsAt
            let sessionStart = sessionReset.map { $0.addingTimeInterval(-5 * 3600) } ?? now.addingTimeInterval(-5 * 3600)
            let session = Aggregation.sessionTotals(events: events, since: sessionStart)
            history = Aggregation.dailyHistory(events: events, now: now, days: 30, calendar: .current)
            let total30 = history.reduce(0) { $0 + $1.costUSD }
            cost = CostSummary(sessionCostUSD: session.cost, sessionTokens: session.tokens,
                               last30DaysCostUSD: total30)
        }

        guard !limits.isEmpty || cost != nil else {
            return .failure(FetchFailure(message: "No recent Codex sessions found"))
        }
        return .success(ProviderSnapshot(account: account.email, plan: plan?.capitalized,
                                         limits: limits, cost: cost, history: history, fetchedAt: Date()))
    }
}
