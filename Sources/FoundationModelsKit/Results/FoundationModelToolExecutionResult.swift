import Foundation

/// A detected repetition of the same tool name and canonical arguments.
public struct FoundationModelToolLoop: Equatable, Sendable {
    public let toolName: String
    public let callFingerprint: String

    public init(toolName: String, callFingerprint: String) {
        self.toolName = toolName
        self.callFingerprint = callFingerprint
    }
}

/// The policy decision produced before a tool output is returned to the model.
public enum FoundationModelToolExecutionResult<Output: Sendable>: Sendable {
    case succeeded(Output, usage: FoundationModelToolExecutionUsage, outputTokenCount: Int?)
    case loopDetected(FoundationModelToolLoop)
    case invalidArguments([FoundationModelToolArgumentIssue])
    case budgetExceeded(FoundationModelToolBudgetExceeded)
    case confirmationRequired(FoundationModelToolConfirmationRequest)
}

extension FoundationModelToolExecutionResult: Equatable where Output: Equatable {}
