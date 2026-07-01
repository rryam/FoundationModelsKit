import Foundation

public enum FoundationModelQuotaStatus: String, Sendable, Hashable, Codable {
    case notApplicable
    case unavailable
    case belowLimit
    case approachingLimit
    case limitReached
    case unsupported
}

public struct FoundationModelQuotaUsage: FoundationModelCapabilityResult, Sendable, Hashable, Codable {
    public let runtime: FoundationModelRuntime
    public let status: FoundationModelQuotaStatus
    public let resetDate: Date?
    public let canRequestLimitIncrease: Bool
    public let unavailableReason: FoundationModelRuntimeUnavailableReason?
    public let metadata: FoundationModelExecutionMetadata

    public init(
        runtime: FoundationModelRuntime,
        status: FoundationModelQuotaStatus,
        resetDate: Date? = nil,
        canRequestLimitIncrease: Bool = false,
        unavailableReason: FoundationModelRuntimeUnavailableReason? = nil,
        metadata: FoundationModelExecutionMetadata = FoundationModelExecutionMetadata()
    ) {
        self.runtime = runtime
        self.status = status
        self.resetDate = resetDate
        self.canRequestLimitIncrease = canRequestLimitIncrease
        self.unavailableReason = unavailableReason
        self.metadata = metadata
    }
}
