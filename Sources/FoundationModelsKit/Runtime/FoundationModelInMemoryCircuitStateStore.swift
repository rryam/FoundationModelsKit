import Foundation

/// An in-memory circuit store for tests and process-lifetime coordination.
public actor FoundationModelInMemoryCircuitStateStore: FoundationModelCircuitStatePersisting {
    private var states: [FoundationModelRuntime: FoundationModelCircuitState]

    public init(states: [FoundationModelRuntime: FoundationModelCircuitState] = [:]) {
        self.states = states
    }

    public func admission(
        for runtime: FoundationModelRuntime,
        at date: Date,
        halfOpenProbeInterval: TimeInterval
    ) -> FoundationModelCircuitAdmission {
        guard let state = states[runtime] else {
            return .permitted(phase: nil, previousState: nil)
        }
        guard state.nextProbeAt <= date else {
            return .rejected(state: state)
        }

        states[runtime] = FoundationModelCircuitState(
            phase: .halfOpen,
            failureCategory: state.failureCategory,
            openedAt: state.openedAt,
            nextProbeAt: date.addingTimeInterval(halfOpenProbeInterval),
            consecutiveFailures: state.consecutiveFailures
        )
        return .permitted(phase: .halfOpen, previousState: state)
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
