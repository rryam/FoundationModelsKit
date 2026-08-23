import Foundation
import FoundationModelsKit

/// One request and outcome captured by ``FoundationModelRecordingTextGenerator``.
public struct FoundationModelTextGenerationRecord: Codable, Equatable, Sendable {
    public let sequence: Int
    public let request: FoundationModelTextGenerationRequest
    public let outcome: FoundationModelRecordedGenerationOutcome

    public init(
        sequence: Int,
        request: FoundationModelTextGenerationRequest,
        outcome: FoundationModelRecordedGenerationOutcome
    ) {
        self.sequence = max(0, sequence)
        self.request = request
        self.outcome = outcome
    }
}
