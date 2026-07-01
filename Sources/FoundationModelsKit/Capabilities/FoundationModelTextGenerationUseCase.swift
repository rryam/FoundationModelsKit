import Foundation

public struct FoundationModelTextGenerationUseCase: FoundationModelCapabilityUseCase {
    public static let descriptor = FoundationModelCapabilityDescriptor(
        id: "foundation-models.generate-text",
        displayName: "Generate Text",
        summary: "Generates text from a prompt using Foundation Models."
    )

    private let provider: any FoundationModelTextGenerating

    public init(provider: any FoundationModelTextGenerating = FoundationModelsTextGenerator()) {
        self.provider = provider
    }

    public func execute(_ request: FoundationModelTextGenerationRequest) async throws -> FoundationModelTextGenerationResult {
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FoundationModelsKitError.invalidRequest("Missing prompt")
        }

        return try await provider.generateText(for: request)
    }
}
