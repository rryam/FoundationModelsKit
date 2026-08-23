import Foundation

/// Limits model-directed tool activity within one turn.
public struct FoundationModelToolExecutionBudget: Equatable, Sendable {
    public let maxCalls: Int
    public let maxRepairs: Int
    public let maxDuration: Duration?
    public let maxOutputTokens: Int?

    public init(
        maxCalls: Int = 16,
        maxRepairs: Int = 2,
        maxDuration: Duration? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.maxCalls = max(0, maxCalls)
        self.maxRepairs = max(0, maxRepairs)
        self.maxDuration = maxDuration.map { max(.zero, $0) }
        self.maxOutputTokens = maxOutputTokens.map { max(0, $0) }
    }
}

/// Identifies whether a generated call is the initial call or a model-authored repair.
public enum FoundationModelToolExecutionAttempt: String, Codable, Equatable, Sendable {
    case initial
    case repair
}

/// The budget dimension that stopped a tool call.
public enum FoundationModelToolBudgetExceeded: Equatable, Sendable {
    case callCount(limit: Int)
    case repairCount(limit: Int)
    case duration(limit: Duration)
    case outputTokens(limit: Int, actual: Int)
    case outputTokenEstimatorRequired(limit: Int)
}

/// Current per-turn policy usage, suitable for evaluation evidence.
public struct FoundationModelToolExecutionUsage: Equatable, Sendable {
    public let callCount: Int
    public let repairCount: Int
    public let elapsed: Duration

    public init(callCount: Int, repairCount: Int, elapsed: Duration) {
        self.callCount = callCount
        self.repairCount = repairCount
        self.elapsed = elapsed
    }
}
