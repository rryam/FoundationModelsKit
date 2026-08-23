import Foundation

/// Stores circuit state independently of a coordinator instance.
public protocol FoundationModelCircuitStatePersisting: Sendable {
    func circuitState(for runtime: FoundationModelRuntime) async -> FoundationModelCircuitState?
    func setCircuitState(
        _ state: FoundationModelCircuitState?,
        for runtime: FoundationModelRuntime
    ) async
}
