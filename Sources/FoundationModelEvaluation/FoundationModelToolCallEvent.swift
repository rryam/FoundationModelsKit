import Foundation

/// One privacy-safe event in the ordered tool-call sequence for an evaluation run.
public struct FoundationModelToolCallEvent: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Equatable, Sendable {
        case requested
        case succeeded
        case rejected
        case failed
    }

    public let sequence: Int
    public let toolName: String
    public let outcome: Outcome

    public init(sequence: Int, toolName: String, outcome: Outcome) {
        self.sequence = max(0, sequence)
        self.toolName = toolName
        self.outcome = outcome
    }
}
