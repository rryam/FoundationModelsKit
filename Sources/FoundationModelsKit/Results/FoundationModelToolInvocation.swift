import Foundation

/// One finalized tool decision and its optional app-defined outcome.
public struct FoundationModelToolInvocation<Outcome: Sendable>: Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case succeeded
        case loopDetected = "loop_detected"
        case invalidArguments = "invalid_arguments"
        case budgetExceeded = "budget_exceeded"
        case authorizationDenied = "authorization_denied"
        case confirmationRequired = "confirmation_required"
        case failed
    }

    public let sequence: Int
    public let identifier: UUID
    public let toolName: String
    public let argumentFingerprint: String
    public let arguments: FoundationModelToolValue?
    public let status: Status
    public let outcome: Outcome?
    public let failure: FoundationModelErrorProjection?
    public let recordedAt: Date
}

extension FoundationModelToolInvocation: Equatable where Outcome: Equatable {}
extension FoundationModelToolInvocation: Codable where Outcome: Codable {}
