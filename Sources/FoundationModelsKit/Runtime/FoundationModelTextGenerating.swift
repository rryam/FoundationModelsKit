import Foundation

public protocol FoundationModelTextGenerating: Sendable {
    func generateText(for request: FoundationModelTextGenerationRequest) async throws -> FoundationModelTextGenerationResult
}
