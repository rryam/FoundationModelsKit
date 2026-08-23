import Foundation

/// A durable circuit store backed by app-owned `UserDefaults`.
public actor FoundationModelDefaultsCircuitStore: FoundationModelCircuitStatePersisting {
    private enum Field {
        static let phase = "phase"
        static let failureCategory = "failureCategory"
        static let openedAt = "openedAt"
        static let nextProbeAt = "nextProbeAt"
        static let consecutiveFailures = "consecutiveFailures"
    }

    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(
        keyPrefix: String = "FoundationModelsKit.executionCircuit"
    ) {
        self.defaults = .standard
        self.keyPrefix = keyPrefix
    }

    public init?(
        suiteName: String,
        keyPrefix: String = "FoundationModelsKit.executionCircuit"
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func circuitState(for runtime: FoundationModelRuntime) -> FoundationModelCircuitState? {
        guard let value = defaults.dictionary(forKey: key(for: runtime)),
              let phaseValue = value[Field.phase] as? String,
              let phase = FoundationModelCircuitState.Phase(rawValue: phaseValue),
              let categoryValue = value[Field.failureCategory] as? String,
              let category = FoundationModelErrorProjection.Category(rawValue: categoryValue),
              let openedAt = value[Field.openedAt] as? Date,
              let nextProbeAt = value[Field.nextProbeAt] as? Date,
              let consecutiveFailures = value[Field.consecutiveFailures] as? Int else {
            return nil
        }

        return FoundationModelCircuitState(
            phase: phase,
            failureCategory: category,
            openedAt: openedAt,
            nextProbeAt: nextProbeAt,
            consecutiveFailures: consecutiveFailures
        )
    }

    public func setCircuitState(
        _ state: FoundationModelCircuitState?,
        for runtime: FoundationModelRuntime
    ) {
        let key = key(for: runtime)
        guard let state else {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(
            [
                Field.phase: state.phase.rawValue,
                Field.failureCategory: state.failureCategory.rawValue,
                Field.openedAt: state.openedAt,
                Field.nextProbeAt: state.nextProbeAt,
                Field.consecutiveFailures: state.consecutiveFailures
            ],
            forKey: key
        )
    }

    private func key(for runtime: FoundationModelRuntime) -> String {
        "\(keyPrefix).\(runtime.rawValue)"
    }
}
