import Foundation
import UsageBarCore

/// Last cumulative token usage + model of one Codex session file.
struct CodexSessionData: Codable {
    let input: Int, cached: Int, output: Int
    let model: String?
}

final class CodexProvider: UsageProvider {
    let id = ProviderID.codex
    private let usageCache = JSONLCache<CodexSessionData?>(persistKey: "codex-usage")

    static func extractModel(from contents: String) -> String? {
        guard let range = contents.range(of: #""model":"([^"]+)""#, options: .regularExpression) else { return nil }
        let match = contents[range]  // "model":"gpt-5.1-codex-mini"
        let parts = match.split(separator: "\"")
        return parts.count >= 4 ? String(parts[3]) : nil
    }

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

        // Cost: last cumulative total_token_usage per session file, priced by the
        // session's actual model (falls back to gpt-5 rates).
        var events: [UsageEvent] = []
        for url in files {
            let data = usageCache.value(forFile: url) { contents -> CodexSessionData? in
                let model = Self.extractModel(from: contents)
                for line in contents.split(separator: "\n").reversed() {
                    if let u = Codex.findTotalTokenUsage(inLine: String(line)) {
                        return CodexSessionData(input: u.input, cached: u.cached, output: u.output, model: model)
                    }
                }
                return nil
            }
            guard let session = data ?? nil, let mtime = fileMTime(url) else { continue }
            let model = session.model ?? "gpt-5"
            let uncached = max(0, session.input - session.cached)
            var cost = Pricing.costUSD(model: model, input: uncached, output: session.output,
                                       cacheWrite: 0, cacheRead: session.cached)
            if cost == 0, session.input + session.output > 0 {
                cost = Pricing.costUSD(model: "gpt-5", input: uncached, output: session.output,
                                       cacheWrite: 0, cacheRead: session.cached)
            }
            events.append(UsageEvent(timestamp: mtime, model: model,
                                     input: session.input, output: session.output,
                                     cacheWrite: 0, cacheRead: session.cached,
                                     dedupeKey: nil, costUSD: cost))
        }
        usageCache.save()

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
