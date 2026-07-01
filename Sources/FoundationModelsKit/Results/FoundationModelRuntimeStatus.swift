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

    enum CodingKeys: String, CodingKey {
        case runtime
        case isSupported
        case isAvailable
        case isRunnableInCurrentProcess
        case authorization
        case reason
        case metadata
    }

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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let runtime = try container.decode(FoundationModelRuntime.self, forKey: .runtime)
        let isSupported = try container.decodeIfPresent(Bool.self, forKey: .isSupported) ?? true
        let isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
        let authorization = try container.decodeIfPresent(
            FoundationModelRuntimeAuthorization.self,
            forKey: .authorization
        ) ?? .notRequired
        let reason = try container.decodeIfPresent(
            FoundationModelRuntimeUnavailableReason.self,
            forKey: .reason
        )
        let metadata = try container.decodeIfPresent(
            FoundationModelExecutionMetadata.self,
            forKey: .metadata
        ) ?? FoundationModelExecutionMetadata()

        self.init(
            runtime: runtime,
            isSupported: isSupported,
            isAvailable: isAvailable,
            authorization: authorization,
            reason: reason,
            metadata: metadata
        )
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
