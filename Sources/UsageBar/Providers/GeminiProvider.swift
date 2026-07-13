import Foundation
import UsageBarCore

/// Gemini CLI exposes no quota or token data locally — this provider shows the
/// active account and a 30-day activity chart (user messages per day) from
/// ~/.gemini/tmp/*/logs.json.
final class GeminiProvider: UsageProvider {
    let id = ProviderID.gemini
    private let logCache = JSONLCache<[Date]>(persistKey: "gemini-logs")

    func fetch() async -> Result<ProviderSnapshot, FetchFailure> {
        let root = home.appendingPathComponent(".gemini")
        guard FileManager.default.fileExists(atPath: root.path) else {
            return .failure(FetchFailure(message: "Gemini not set up (~/.gemini missing)"))
        }
        let account = Self.activeAccount(root: root)

        var dates: [Date] = []
        let tmp = root.appendingPathComponent("tmp")
        let sessionDirs = (try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for dir in sessionDirs {
            let log = dir.appendingPathComponent("logs.json")
            guard FileManager.default.fileExists(atPath: log.path) else { continue }
            let parsed = logCache.value(forFile: log) { contents -> [Date] in
                guard let data = contents.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else { return [] }
                return arr.compactMap { entry in
                    guard entry["type"] as? String == "user" else { return nil }
                    return ClaudeLimits.parseISODate(entry["timestamp"] as? String)
                }
            }
            if let parsed { dates.append(contentsOf: parsed) }
        }
        logCache.save()

        let now = Date()
        let cutoff = now.addingTimeInterval(-31 * 24 * 3600)
        let events = dates.filter { $0 > cutoff }.map {
            // costUSD carries "1 request" — the snapshot is marked costUnit: .requests.
            UsageEvent(timestamp: $0, model: "gemini", input: 0, output: 0,
                       cacheWrite: 0, cacheRead: 0, dedupeKey: nil, costUSD: 1)
        }
        guard account != nil || !events.isEmpty else {
            return .failure(FetchFailure(message: "No local Gemini activity found"))
        }
        let history = Aggregation.dailyHistory(events: events, now: now, days: 30, calendar: .current)
        return .success(ProviderSnapshot(account: account, plan: nil, limits: [],
                                         cost: nil, history: history, fetchedAt: now,
                                         costUnit: .requests))
    }

    static func activeAccount(root: URL) -> String? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("google_accounts.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["active"] as? String
    }
}
