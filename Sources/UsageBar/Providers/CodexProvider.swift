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
    private let limitsCache = JSONLCache<Codex.RateLimitObservation?>(persistKey: "codex-general-limits-v1")
    private var lastGeneralLimits: Codex.RateLimitObservation?

    func fetch() async -> Result<ProviderSnapshot, FetchFailure> {
        let sessionsRoot = home.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: sessionsRoot.path) else {
            return .failure(FetchFailure(message: "Codex not set up (~/.codex/sessions missing)"))
        }
        let authData = try? Data(contentsOf: home.appendingPathComponent(".codex/auth.json"))
        let account: (email: String?, plan: String?) =
            authData.flatMap { Codex.parseAuth($0) } ?? (email: nil, plan: nil)

        let now = Date()
        // Stat once, then sort — the old comparator re-hit the filesystem on every
        // comparison. Newest first.
        let dated = jsonlFiles(under: sessionsRoot, modifiedAfter: nil)
            .compactMap { url in fileMTime(url).map { (url: url, mtime: $0) } }
            .sorted { $0.mtime > $1.mtime }
        guard let newest = dated.first else {
            return .failure(FetchFailure(message: "No Codex sessions in ~/.codex/sessions"))
        }

        // Model-specific buckets (for example Spark) are independent of the
        // general quota. Search every file, caching unchanged parses, and select
        // by the quota event date rather than unrelated session-file activity.
        if let observed = Codex.latestRateLimits(inFiles: dated.map(\.url), load: { url in
            limitsCache.value(forFile: url) { Codex.rateLimitObservation(in: $0) } ?? nil
        }), lastGeneralLimits.map({ observed.observedAt >= $0.observedAt }) ?? true {
            lastGeneralLimits = observed
        }
        limitsCache.save()
        var limits = lastGeneralLimits?.limits ?? []
        let plan = lastGeneralLimits?.plan ?? account.plan
        // A window whose reset already passed says nothing about current usage, so
        // flag it instead of presenting a weeks-old percentage as live.
        limits = limits.map { $0.hasExpired(now: now) ? $0.markedStale() : $0 }

        // Cost: last cumulative total_token_usage per session file, priced by the
        // session's actual model (falls back to gpt-5 rates).
        let cutoff = now.addingTimeInterval(-31 * 24 * 3600)
        var events: [UsageEvent] = []
        for (url, mtime) in dated where mtime > cutoff {
            let data = usageCache.value(forFile: url) { contents -> CodexSessionData? in
                let model = Codex.extractModel(from: contents)
                for line in contents.split(separator: "\n").reversed() {
                    if let u = Codex.findTotalTokenUsage(inLine: String(line)) {
                        return CodexSessionData(input: u.input, cached: u.cached, output: u.output, model: model)
                    }
                }
                return nil
            }
            guard let session = data ?? nil else { continue }
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
        var modelBreakdown: [ModelCost] = []
        if !events.isEmpty {
            let cutoff30 = now.addingTimeInterval(-30 * 24 * 3600)
            // Derived from whichever limit window is actually live, not from a bar
            // named "Session" — Codex no longer ships a 5h window at all.
            let window = UsageWindow.current(limits: limits, now: now)
            let session = Aggregation.sessionTotals(events: events, since: window.start)
            history = Aggregation.dailyHistory(events: events, now: now, days: 30, calendar: .current)
            modelBreakdown = Aggregation.modelBreakdown(events: events, since: cutoff30)
            let total30 = history.reduce(0) { $0 + $1.costUSD }
            cost = CostSummary(sessionCostUSD: session.cost, sessionTokens: session.tokens,
                               last30DaysCostUSD: total30, sessionLabel: window.label)
        }

        guard !limits.isEmpty || cost != nil else {
            return .failure(FetchFailure(message: "No usage data in recent Codex sessions"))
        }
        return .success(ProviderSnapshot(account: account.email, plan: plan?.capitalized,
                                         limits: limits, cost: cost, history: history,
                                         fetchedAt: now, dataThrough: lastGeneralLimits?.observedAt ?? newest.mtime,
                                         limitsNote: limits.isEmpty
                                             ? "No general Codex quota found in local sessions — model-specific quotas are not shown here."
                                             : nil,
                                         modelBreakdown: modelBreakdown))
    }
}
