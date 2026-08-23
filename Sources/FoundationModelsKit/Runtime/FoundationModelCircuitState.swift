import Foundation

/// Persistable state for one Foundation Models runtime circuit.
public struct FoundationModelCircuitState: Sendable, Hashable, Codable {
    public enum Phase: String, Sendable, Hashable, Codable {
        case open
        case halfOpen
    }

    public let phase: Phase
    public let failureCategory: FoundationModelErrorProjection.Category
    public let openedAt: Date
    public let nextProbeAt: Date
    public let consecutiveFailures: Int

    public init(
        phase: Phase,
        failureCategory: FoundationModelErrorProjection.Category,
        openedAt: Date,
        nextProbeAt: Date,
        consecutiveFailures: Int
    ) {
        self.phase = phase
        self.failureCategory = failureCategory
        self.openedAt = openedAt
        self.nextProbeAt = nextProbeAt
        self.consecutiveFailures = consecutiveFailures
    }
}
