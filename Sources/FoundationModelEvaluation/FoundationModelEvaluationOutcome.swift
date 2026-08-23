import Foundation

/// The terminal class of an evaluated generation.
public enum FoundationModelEvaluationOutcome: String, Codable, Equatable, Sendable {
    /// Generation completed; app-owned validators decide `finalSuccess`.
    case completed

    /// The framework reported a refusal or guardrail violation.
    case refused

    /// Generation ended with another typed or unclassified error.
    case failed

    /// The evaluation task was cancelled before generation completed.
    case cancelled
}
