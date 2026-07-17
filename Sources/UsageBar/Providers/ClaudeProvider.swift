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
            lastLimits = limits
            lastExtra = extraUsage
        } catch {
            limitsError = (error as? FetchFailure)?.message ?? error.localizedDescription
            // Transient failure (e.g. rate limit): keep the last good bars visible
            // rather than blanking them. Cost still refreshes below.
            if !lastLimits.isEmpty {
                limits = lastLimits
                extraUsage = lastExtra
                limitsError = nil
            }
        }

        let sessionReset = limits.first { $0.label == "Session" }?.resetsAt
        let cost = scanCost(sessionResetsAt: sessionReset)

        if limits.isEmpty, let limitsError {
            // Degrade: local-only data if we have it, otherwise report the failure.
            if cost == nil { return .failure(FetchFailure(message: limitsError)) }
        }
        return .success(ProviderSnapshot(account: account, plan: plan, limits: limits,
                                         cost: cost, history: historyCache, fetchedAt: Date(),
                                         extraUsage: extraUsage,
                                         modelBreakdown: modelBreakdownCache,
                                         projectBreakdown: projectBreakdownCache))
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
    private var modelBreakdownCache: [ModelCost] = []
    private var projectBreakdownCache: [ProjectCost] = []
    private var lastLimits: [LimitBar] = []
    private var lastExtra: ExtraUsage? = nil

    private func scanCost(sessionResetsAt: Date?) -> CostSummary? {
        let root = home.appendingPathComponent(".claude/projects")
        let cutoff = Date().addingTimeInterval(-31 * 24 * 3600)
        let files = jsonlFiles(under: root, modifiedAfter: cutoff)
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
        let sessionStart = sessionResetsAt.map { $0.addingTimeInterval(-5 * 3600) } ?? now.addingTimeInterval(-5 * 3600)
        let session = Aggregation.sessionTotals(events: events, since: sessionStart)
        historyCache = Aggregation.dailyHistory(events: events, now: now, days: 30, calendar: .current)
        modelBreakdownCache = Aggregation.modelBreakdown(events: events, since: cutoff30)
        projectBreakdownCache = Aggregation.topProjects(projectCosts, limit: 8)
        let total30 = historyCache.reduce(0) { $0 + $1.costUSD }
        return CostSummary(sessionCostUSD: session.cost, sessionTokens: session.tokens,
                           last30DaysCostUSD: total30)
    }
}
