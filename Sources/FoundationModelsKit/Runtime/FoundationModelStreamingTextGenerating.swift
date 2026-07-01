import Foundation

public protocol StreamingFoundationModelTextGenerating: Sendable {
    func streamText(
        for request: FoundationModelStreamingTextGenerationRequest,
        onPartialResponse: @escaping @Sendable (String) async -> Void
    ) async throws -> FoundationModelTextGenerationResult
}
