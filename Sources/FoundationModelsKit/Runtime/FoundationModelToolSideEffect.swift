import Foundation

/// App-owned protection for a tool that may cause external side effects.
public enum FoundationModelToolSideEffectProtection: Equatable, Sendable {
    /// Ask the app for confirmation immediately before executing the tool.
    case confirmation

    /// Reserve an app-defined key before execution so the turn cannot reuse it with different arguments.
    case idempotency(key: String)
}

/// Declares whether a tool call is read-only or protected against duplicate side effects.
public enum FoundationModelToolEffect: Equatable, Sendable {
    case readOnly
    case sideEffect(FoundationModelToolSideEffectProtection)
}

/// A privacy-safe confirmation request. Generated arguments are delivered separately to the confirmer.
public struct FoundationModelToolConfirmationRequest: Equatable, Sendable {
    public let toolName: String
    public let callFingerprint: String

    public init(toolName: String, callFingerprint: String) {
        self.toolName = toolName
        self.callFingerprint = callFingerprint
    }
}

/// Lets the app present its own confirmation UI and authorization policy.
public protocol FoundationModelToolExecutionConfirming: Sendable {
    func confirm(
        _ request: FoundationModelToolConfirmationRequest,
        arguments: FoundationModelToolValue
    ) async -> Bool
}
