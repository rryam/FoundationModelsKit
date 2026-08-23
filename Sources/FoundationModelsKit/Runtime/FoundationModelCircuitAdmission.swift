import Foundation

/// The atomic decision returned when a coordinator asks a circuit store to admit a request.
public enum FoundationModelCircuitAdmission: Sendable, Equatable {
    /// The route may execute. `previousState` is retained for cancellation recovery.
    case permitted(
        phase: FoundationModelCircuitState.Phase?,
        previousState: FoundationModelCircuitState?
    )

    /// Another request must not execute this route before the stored probe date.
    case rejected(state: FoundationModelCircuitState)
}
