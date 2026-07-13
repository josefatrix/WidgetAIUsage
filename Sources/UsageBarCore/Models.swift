import Foundation

public struct LimitBar: Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let percent: Double   // 0...100
    public let resetsAt: Date?
    public init(label: String, percent: Double, resetsAt: Date?) {
        self.label = label; self.percent = percent; self.resetsAt = resetsAt
    }
}

public struct DailyCost: Equatable {
    public let day: Date
    public let costUSD: Double
    public let tokens: Int
    public init(day: Date, costUSD: Double, tokens: Int) {
        self.day = day; self.costUSD = costUSD; self.tokens = tokens
    }
}

public struct CostSummary: Equatable {
    public let sessionCostUSD: Double
    public let sessionTokens: Int
    public let last30DaysCostUSD: Double
    public init(sessionCostUSD: Double, sessionTokens: Int, last30DaysCostUSD: Double) {
        self.sessionCostUSD = sessionCostUSD
        self.sessionTokens = sessionTokens
        self.last30DaysCostUSD = last30DaysCostUSD
    }
}

public struct ProviderSnapshot {
    public let account: String?
    public let plan: String?
    public let limits: [LimitBar]
    public let cost: CostSummary?
    public let history: [DailyCost]
    public let fetchedAt: Date
    public init(account: String?, plan: String?, limits: [LimitBar],
                cost: CostSummary?, history: [DailyCost], fetchedAt: Date) {
        self.account = account; self.plan = plan; self.limits = limits
        self.cost = cost; self.history = history; self.fetchedAt = fetchedAt
    }
}
