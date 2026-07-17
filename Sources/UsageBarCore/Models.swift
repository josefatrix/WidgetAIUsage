import Foundation

public struct LimitBar: Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let percent: Double   // 0...100
    public let resetsAt: Date?
    public let severity: String?  // API-provided: "normal", "warning", ... (nil = use thresholds)
    public let windowMinutes: Int?  // full window length, for burn-rate projection
    public init(label: String, percent: Double, resetsAt: Date?,
                severity: String? = nil, windowMinutes: Int? = nil) {
        self.label = label; self.percent = percent; self.resetsAt = resetsAt
        self.severity = severity; self.windowMinutes = windowMinutes
    }
}

public struct ModelCost: Equatable {
    public let model: String
    public let costUSD: Double
    public let tokens: Int
    public init(model: String, costUSD: Double, tokens: Int) {
        self.model = model; self.costUSD = costUSD; self.tokens = tokens
    }
}

public struct ProjectCost: Equatable {
    public let project: String
    public let costUSD: Double
    public init(project: String, costUSD: Double) {
        self.project = project; self.costUSD = costUSD
    }
}

public struct Forecast: Equatable {
    public let hitDate: Date
    public let willHitBeforeReset: Bool
    public init(hitDate: Date, willHitBeforeReset: Bool) {
        self.hitDate = hitDate; self.willHitBeforeReset = willHitBeforeReset
    }
}

public struct ExtraUsage: Equatable {
    public let usedUSD: Double
    public let limitUSD: Double
    public let utilization: Double
    public init(usedUSD: Double, limitUSD: Double, utilization: Double) {
        self.usedUSD = usedUSD; self.limitUSD = limitUSD; self.utilization = utilization
    }
}

public enum CostUnit { case usd, requests }

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
    public let extraUsage: ExtraUsage?
    public let costUnit: CostUnit
    public let modelBreakdown: [ModelCost]
    public let projectBreakdown: [ProjectCost]
    public init(account: String?, plan: String?, limits: [LimitBar],
                cost: CostSummary?, history: [DailyCost], fetchedAt: Date,
                extraUsage: ExtraUsage? = nil, costUnit: CostUnit = .usd,
                modelBreakdown: [ModelCost] = [], projectBreakdown: [ProjectCost] = []) {
        self.account = account; self.plan = plan; self.limits = limits
        self.cost = cost; self.history = history; self.fetchedAt = fetchedAt
        self.extraUsage = extraUsage; self.costUnit = costUnit
        self.modelBreakdown = modelBreakdown; self.projectBreakdown = projectBreakdown
    }
}
