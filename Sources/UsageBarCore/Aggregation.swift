import Foundation

public enum Aggregation {
    public static func dedupe(_ events: [UsageEvent]) -> [UsageEvent] {
        var seen = Set<String>()
        return events.filter { e in
            guard let k = e.dedupeKey else { return true }
            return seen.insert(k).inserted
        }
    }

    public static func dailyHistory(events: [UsageEvent], now: Date, days: Int, calendar: Calendar) -> [DailyCost] {
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: (Double, Int)] = [:]
        for e in events {
            let day = calendar.startOfDay(for: e.timestamp)
            let cur = buckets[day] ?? (0, 0)
            buckets[day] = (cur.0 + e.costUSD, cur.1 + e.input + e.output)
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let v = buckets[day] ?? (0, 0)
            return DailyCost(day: day, costUSD: v.0, tokens: v.1)
        }
    }

    public static func sessionTotals(events: [UsageEvent], since: Date) -> (cost: Double, tokens: Int) {
        let recent = events.filter { $0.timestamp >= since }
        return (recent.reduce(0) { $0 + $1.costUSD },
                recent.reduce(0) { $0 + $1.input + $1.output })
    }

    public static func modelBreakdown(events: [UsageEvent], since: Date) -> [ModelCost] {
        var byModel: [String: (Double, Int)] = [:]
        for e in events where e.timestamp >= since {
            let cur = byModel[e.model] ?? (0, 0)
            byModel[e.model] = (cur.0 + e.costUSD, cur.1 + e.input + e.output)
        }
        return byModel
            .map { ModelCost(model: $0.key, costUSD: $0.value.0, tokens: $0.value.1) }
            .sorted { $0.costUSD > $1.costUSD }
    }

    public static func topProjects(_ costs: [String: Double], limit: Int) -> [ProjectCost] {
        costs.map { ProjectCost(project: $0.key, costUSD: $0.value) }
            .sorted { $0.costUSD > $1.costUSD }
            .prefix(limit)
            .map { $0 }
    }

    public static func lastPathComponent(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.last.map(String.init) ?? path
    }
}
