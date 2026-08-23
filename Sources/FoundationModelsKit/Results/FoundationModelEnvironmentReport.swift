import Foundation

/// Structured preflight facts and known blockers for one requested runtime.
public struct FoundationModelEnvironmentReport: Codable, Equatable, Sendable {
    public enum Limitation: String, Codable, Equatable, Sendable {
        case toolSpecificAssetReadinessNotExposed = "tool_specific_asset_readiness_not_exposed"
        case simulatorHostOperatingSystemNotExposed = "simulator_host_operating_system_not_exposed"
        case virtualizationStateNotExposed = "virtualization_state_not_exposed"
    }

    public let capturedAt: Date
    public let environment: FoundationModelRuntimeEnvironment
    public let runtimeStatus: FoundationModelRuntimeStatus
    public let issues: [FoundationModelEnvironmentIssue]
    public let limitations: [Limitation]

    /// True when public preflight signals show no blocker. The request itself remains authoritative.
    public var canAttemptRequest: Bool {
        runtimeStatus.isRunnableInCurrentProcess
            && !issues.contains { $0.severity == .error }
    }

    public init(
        capturedAt: Date,
        environment: FoundationModelRuntimeEnvironment,
        runtimeStatus: FoundationModelRuntimeStatus,
        issues: [FoundationModelEnvironmentIssue],
        limitations: [Limitation]
    ) {
        self.capturedAt = capturedAt
        self.environment = environment
        self.runtimeStatus = runtimeStatus
        self.issues = issues
        self.limitations = limitations
    }
}
