import Foundation

/// An in-memory circuit store for tests and process-lifetime coordination.
public actor FoundationModelInMemoryCircuitStateStore: FoundationModelCircuitStatePersisting {
    private var states: [FoundationModelRuntime: FoundationModelCircuitState]

    public init(states: [FoundationModelRuntime: FoundationModelCircuitState] = [:]) {
        self.states = states
    }

    public func circuitState(for runtime: FoundationModelRuntime) -> FoundationModelCircuitState? {
        states[runtime]
    }

    public func setCircuitState(
        _ state: FoundationModelCircuitState?,
        for runtime: FoundationModelRuntime
    ) {
        states[runtime] = state
    }
}
