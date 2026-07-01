import Foundation

public enum FoundationModelAvailabilityUnavailableReason: String, Sendable, Hashable, Codable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
}

public struct FoundationModelAvailability: FoundationModelCapabilityResult, Sendable, Hashable, Codable {
    public let isAvailable: Bool
    public let reason: FoundationModelAvailabilityUnavailableReason?
    public let metadata: FoundationModelExecutionMetadata

    public init(
        isAvailable: Bool,
        reason: FoundationModelAvailabilityUnavailableReason? = nil,
        metadata: FoundationModelExecutionMetadata = FoundationModelExecutionMetadata()
    ) {
        self.isAvailable = isAvailable
        self.reason = reason
        self.metadata = metadata
    }
}
