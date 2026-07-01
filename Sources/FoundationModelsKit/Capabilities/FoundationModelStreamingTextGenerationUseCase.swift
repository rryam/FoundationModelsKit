import Foundation

public struct FoundationModelStreamingTextGenerationUseCase: Sendable {
    public static let descriptor = FoundationModelCapabilityDescriptor(
        id: "foundation-models.stream-text",
        displayName: "Stream Text",
        summary: "Streams text generation updates using Foundation Models."
    )

    private let provider: any StreamingFoundationModelTextGenerating

    public init(provider: any StreamingFoundationModelTextGenerating = FoundationModelsStreamingTextGenerator()) {
        self.provider = provider
    }

    public func execute(
        _ request: FoundationModelStreamingTextGenerationRequest,
        onPartialResponse: @escaping @Sendable (String) async -> Void
    ) async throws -> FoundationModelTextGenerationResult {
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FoundationModelsKitError.invalidRequest("Missing prompt")
        }

        return try await provider.streamText(
            for: request,
            onPartialResponse: onPartialResponse
        )
    }
}
