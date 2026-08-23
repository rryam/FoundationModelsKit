import Foundation

/// One known environment blocker with machine-readable recovery actions.
public struct FoundationModelEnvironmentIssue: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Equatable, Sendable {
        case unsupportedOperatingSystem = "unsupported_operating_system"
        case unsupportedToolchain = "unsupported_toolchain"
        case deviceNotEligible = "device_not_eligible"
        case appleIntelligenceNotEnabled = "apple_intelligence_not_enabled"
        case modelNotReady = "model_not_ready"
        case systemNotReady = "system_not_ready"
        case missingPrivateCloudEntitlement = "missing_private_cloud_entitlement"
        case externalBootVolume = "external_boot_volume"
        case deploymentTargetBelowRequired = "deployment_target_below_required"
        case sdkRuntimeVersionMismatch = "sdk_runtime_version_mismatch"
        case unknownRuntimeState = "unknown_runtime_state"
    }

    public enum Severity: String, Codable, Equatable, Sendable {
        case warning
        case error
    }

    public enum Action: String, Codable, Equatable, Sendable {
        case useSupportedOperatingSystem = "use_supported_operating_system"
        case useSupportedToolchain = "use_supported_toolchain"
        case useEligibleDevice = "use_eligible_device"
        case enableAppleIntelligence = "enable_apple_intelligence"
        case waitForModelAssets = "wait_for_model_assets"
        case addPrivateCloudComputeEntitlement = "add_private_cloud_compute_entitlement"
        case bootFromInternalVolume = "boot_from_internal_volume"
        case alignXcodeSDKSimulatorAndHost = "align_xcode_sdk_simulator_and_host"
        case inspectRuntimeStatus = "inspect_runtime_status"
        case collectSysdiagnoseAndFileFeedback = "collect_sysdiagnose_and_file_feedback"
    }

    public let code: Code
    public let severity: Severity
    public let actions: [Action]

    public init(code: Code, severity: Severity, actions: [Action]) {
        self.code = code
        self.severity = severity
        self.actions = actions
    }
}
