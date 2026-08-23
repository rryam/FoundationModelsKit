import Foundation
import FoundationModelsKit

/// The stable result retained for one recorded text-generation request.
public enum FoundationModelRecordedGenerationOutcome: Codable, Equatable, Sendable {
    case success(FoundationModelTextGenerationResult)
    case failure(FoundationModelErrorProjection)
    case cancelled
}
