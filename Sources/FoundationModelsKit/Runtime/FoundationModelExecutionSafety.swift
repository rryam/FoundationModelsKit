import Foundation

/// Describes whether another runtime may safely receive a request after an attempted execution fails.
public enum FoundationModelExecutionSafety: String, Sendable, Hashable, Codable {
    /// The request has no side effects, or the caller guarantees that repeating it is idempotent.
    case readOnlyOrIdempotent

    /// The request may have performed a side effect before reporting a failure.
    case mayHaveSideEffects
}
