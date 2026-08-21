import Foundation

/// What a limit actually governs. Needed because "Weekly" and "Fable" are both
/// 7-day windows, and only one of them belongs on the dial.
public enum LimitKind: String, Codable {
    case session   // the short rolling window
    case overall   // the long window, across everything
    case scoped    // a long window for one model
}

/// How alarmed to be about a limit. Deliberately the *maximum* of what the
/// provider says and what the percentage says: Anthropic reports "normal" well
/// past 60%, so trusting the API alone left a bar at 65% the same calm blue as
/// one at 5% — a meter whose colour never moved.
public enum LimitLevel: Int, Comparable, Sendable {
    case normal = 0, warning = 1, critical = 2, stale = 3

    public static let warningAt: Double = 60
    public static let criticalAt: Double = 85

    public static func < (a: LimitLevel, b: LimitLevel) -> Bool { a.rawValue < b.rawValue }

    public static func of(percent: Double, severity: String?) -> LimitLevel {
        // Stale is a state rather than a severity: the number is not current, so
        // no threshold applies to it.
        if severity == "stale" { return .stale }
        let fromPercent: LimitLevel = percent >= criticalAt ? .critical
            : percent >= warningAt ? .warning : .normal
        let fromAPI: LimitLevel
        switch severity {
        case "warning": fromAPI = .warning
        case "exceeded", "critical", "error": fromAPI = .critical
        default: fromAPI = .normal
        }
        return max(fromPercent, fromAPI)
    }
}

public struct LimitBar: Equatable, Identifiable, Codable {
    public var id: String { label }
    public let label: String
    public let percent: Double   // 0...100
    public let resetsAt: Date?
    public let severity: String?  // API-provided: "normal", "warning", ... (nil = use thresholds)
    public let windowMinutes: Int?  // full window length, for burn-rate projection
    /// Optional so caches written before this existed still decode.
    public let kind: LimitKind?
    public init(label: String, percent: Double, resetsAt: Date?,
                severity: String? = nil, windowMinutes: Int? = nil,
                kind: LimitKind? = nil) {
        self.label = label; self.percent = percent; self.resetsAt = resetsAt
        self.severity = severity; self.windowMinutes = windowMinutes; self.kind = kind
    }

    /// True once the window this percentage belongs to has closed. The number is
    /// then a leftover from a window that already reset — real usage is unknown,
    /// not zero — so callers must not present it as the current figure.
    public var level: LimitLevel { LimitLevel.of(percent: percent, severity: severity) }

    public func hasExpired(now: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }

    /// Same bar flagged as no-longer-current, so the UI can grey it out and drop
    /// the forecast while still showing the last figure we actually observed.
    public func markedStale() -> LimitBar {
        LimitBar(label: label, percent: percent, resetsAt: resetsAt,
                 severity: "stale", windowMinutes: windowMinutes, kind: kind)
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
    public let projectedPercentAtReset: Double
    public init(hitDate: Date, willHitBeforeReset: Bool, projectedPercentAtReset: Double) {
        self.hitDate = hitDate
        self.willHitBeforeReset = willHitBeforeReset
        self.projectedPercentAtReset = projectedPercentAtReset
    }
}

public struct ExtraUsage: Equatable, Codable {
    public let usedUSD: Double
    public let limitUSD: Double
    public let utilization: Double
    public init(usedUSD: Double, limitUSD: Double, utilization: Double) {
        self.usedUSD = usedUSD; self.limitUSD = limitUSD; self.utilization = utilization
    }
}

/// What the "cost" numbers on a snapshot actually count. Providers that expose no
/// billing (or no quota at all) report activity instead, and the UI labels it.
public enum CostUnit {
    case usd, requests, conversations

    public var pluralNoun: String {
        switch self {
        case .usd: return "dollars"
        case .requests: return "requests"
        case .conversations: return "conversations"
        }
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
    /// What the session figure actually covers. Not every provider still has a
    /// 5h window (Codex now only exposes a weekly one), so the tile says so.
    public let sessionLabel: String
    public init(sessionCostUSD: Double, sessionTokens: Int, last30DaysCostUSD: Double,
                sessionLabel: String = "This session") {
        self.sessionCostUSD = sessionCostUSD
        self.sessionTokens = sessionTokens
        self.last30DaysCostUSD = last30DaysCostUSD
        self.sessionLabel = sessionLabel
    }
}

public struct ProviderSnapshot {
    public let account: String?
    public let plan: String?
    public let limits: [LimitBar]
    public let cost: CostSummary?
    public let history: [DailyCost]
    public let fetchedAt: Date
    /// Newest moment the underlying data actually covers. Providers that scrape
    /// local logs set this to the newest record they saw; live APIs leave it nil
    /// (fetching *is* observing). Without it a 3-week-old log reads "just now".
    public let dataThrough: Date?
    /// Why the limit bars are missing or old, when we know. Shown verbatim — an
    /// empty dial with no explanation is the worst of both worlds.
    public let limitsNote: String?
    public let extraUsage: ExtraUsage?
    public let costUnit: CostUnit
    public let modelBreakdown: [ModelCost]
    public let projectBreakdown: [ProjectCost]
    public init(account: String?, plan: String?, limits: [LimitBar],
                cost: CostSummary?, history: [DailyCost], fetchedAt: Date,
                dataThrough: Date? = nil, limitsNote: String? = nil,
                extraUsage: ExtraUsage? = nil, costUnit: CostUnit = .usd,
                modelBreakdown: [ModelCost] = [], projectBreakdown: [ProjectCost] = []) {
        self.account = account; self.plan = plan; self.limits = limits
        self.cost = cost; self.history = history; self.fetchedAt = fetchedAt
        self.dataThrough = dataThrough; self.limitsNote = limitsNote
        self.extraUsage = extraUsage; self.costUnit = costUnit
        self.modelBreakdown = modelBreakdown; self.projectBreakdown = projectBreakdown
    }

    /// The moment this snapshot describes — what "Updated …" should count from.
    public var asOf: Date { dataThrough ?? fetchedAt }

    public func isStale(now: Date, threshold: TimeInterval) -> Bool {
        now.timeIntervalSince(asOf) > threshold
    }
}
