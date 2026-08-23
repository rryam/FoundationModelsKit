import Foundation

/// Timing policy for request-level circuit breaking and half-open probes.
public struct FoundationModelExecutionPolicy: Sendable, Hashable, Codable {
    /// Cooldown used when Foundation Models does not provide a reset date.
    public let defaultCooldown: TimeInterval

    /// Minimum delay before another probe after a failed half-open attempt.
    public let halfOpenProbeInterval: TimeInterval

    public init(
        defaultCooldown: TimeInterval = 15 * 60,
        halfOpenProbeInterval: TimeInterval = 30 * 60
    ) {
        self.defaultCooldown = defaultCooldown
        self.halfOpenProbeInterval = halfOpenProbeInterval
    }

    public static let `default` = FoundationModelExecutionPolicy()

    public static let circuitBreakingCategories: Set<FoundationModelErrorProjection.Category> = [
        .rateLimited,
        .quotaLimitReached,
        .networkFailure,
        .serviceUnavailable
    ]
}
