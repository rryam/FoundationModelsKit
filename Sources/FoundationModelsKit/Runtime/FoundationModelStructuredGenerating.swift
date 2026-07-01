import Foundation
import FoundationModels

public protocol FoundationModelStructuredGenerating: Sendable {
    func generate<Output: Generable & Sendable>(
        _ type: Output.Type,
        for request: FoundationModelStructuredGenerationRequest<Output>
    ) async throws -> FoundationModelStructuredGenerationResult<Output>
}
