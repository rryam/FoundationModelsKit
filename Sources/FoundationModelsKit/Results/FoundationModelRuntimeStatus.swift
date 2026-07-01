import Foundation

public enum FoundationModelRuntimeUnavailableReason: String, Sendable, Hashable, Codable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case systemNotReady
    case unsupportedOperatingSystem
    case unsupportedToolchain
    case missingEntitlement
    case unknown
}

public enum FoundationModelRuntimeAuthorization: String, Sendable, Hashable, Codable {
    case notRequired
    case granted
    case missing
    case unknown
}

public struct FoundationModelRuntimeStatus: FoundationModelCapabilityResult, Sendable, Hashable, Codable {
    public let runtime: FoundationModelRuntime
    public let isSupported: Bool
    public let isAvailable: Bool
    public let isRunnableInCurrentProcess: Bool
    public let authorization: FoundationModelRuntimeAuthorization
    public let reason: FoundationModelRuntimeUnavailableReason?
    public let metadata: FoundationModelExecutionMetadata

    public init(
        runtime: FoundationModelRuntime,
        isSupported: Bool = true,
        isAvailable: Bool,
        authorization: FoundationModelRuntimeAuthorization = .notRequired,
        reason: FoundationModelRuntimeUnavailableReason? = nil,
        metadata: FoundationModelExecutionMetadata = FoundationModelExecutionMetadata()
    ) {
        self.runtime = runtime
        self.isSupported = isSupported
        self.isAvailable = isAvailable
        let hasRequiredAuthorization = authorization == .granted
            || (runtime == .onDevice && authorization == .notRequired)
        self.isRunnableInCurrentProcess = isSupported
            && isAvailable
            && hasRequiredAuthorization
        self.authorization = authorization
        self.reason = reason ?? Self.authorizationReason(
            runtime: runtime,
            authorization: authorization
        )
        self.metadata = metadata
    }

    private static func authorizationReason(
        runtime: FoundationModelRuntime,
        authorization: FoundationModelRuntimeAuthorization
    ) -> FoundationModelRuntimeUnavailableReason? {
        guard runtime == .privateCloudCompute else { return nil }
        switch authorization {
        case .missing:
            return .missingEntitlement
        case .unknown, .notRequired:
            return .unknown
        case .granted:
            return nil
        }
    }
}
