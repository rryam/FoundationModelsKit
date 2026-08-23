import Foundation

/// Stores circuit state independently of a coordinator instance.
public protocol FoundationModelCircuitStatePersisting: Sendable {
    /// Atomically admits a closed circuit or reserves one half-open probe.
    func admission(
        for runtime: FoundationModelRuntime,
        at date: Date,
        halfOpenProbeInterval: TimeInterval
    ) async -> FoundationModelCircuitAdmission

    func circuitState(for runtime: FoundationModelRuntime) async -> FoundationModelCircuitState?
    func setCircuitState(
        _ state: FoundationModelCircuitState?,
        for runtime: FoundationModelRuntime
    ) async
}
