import Foundation

/// The point in tool execution at which the app re-evaluates authorization.
public enum FoundationModelToolAuthorizationPhase: String, Codable, Equatable, Sendable {
    /// Before presenting a confirmation request for a side effect.
    case beforeConfirmation

    /// Immediately before app-owned tool code executes.
    case beforeExecution
}

/// A privacy-safe request for an app-owned authorization decision.
///
/// Generated arguments are delivered separately to the authorizer so apps can avoid retaining
/// sensitive values in authorization logs.
public struct FoundationModelToolAuthorizationRequest: Equatable, Sendable {
    public let toolName: String
    public let callFingerprint: String
    public let phase: FoundationModelToolAuthorizationPhase

    public init(
        toolName: String,
        callFingerprint: String,
        phase: FoundationModelToolAuthorizationPhase
    ) {
        self.toolName = toolName
        self.callFingerprint = callFingerprint
        self.phase = phase
    }
}

/// App-defined, non-sensitive evidence explaining why a tool call was not authorized.
public struct FoundationModelToolAuthorizationDenial: Equatable, Sendable {
    public let code: String

    public init(code: String = "denied") {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        self.code = normalizedCode.isEmpty ? "denied" : normalizedCode
    }
}

/// The app-owned authorization decision for a generated tool call.
public enum FoundationModelToolAuthorizationDecision: Equatable, Sendable {
    case allowed
    case denied(FoundationModelToolAuthorizationDenial)
}

/// Re-evaluates whether the current app context may execute a generated tool call.
///
/// Authorization is distinct from platform permission and user confirmation. Implementations can
/// capture app-specific actor, capability, resource, and revocation state without exposing those
/// domain concepts to the model or this package. This hook supervises model-directed execution; it
/// does not replace authorization enforcement inside the app service that performs the operation.
public protocol FoundationModelToolExecutionAuthorizing: Sendable {
    func authorize(
        _ request: FoundationModelToolAuthorizationRequest,
        arguments: FoundationModelToolValue
    ) async -> FoundationModelToolAuthorizationDecision
}
