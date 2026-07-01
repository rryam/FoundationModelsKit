import Foundation
import FoundationModels

public struct FoundationModelStructuredGenerationUseCase<Output: Generable & Sendable>: FoundationModelCapabilityUseCase {
    public static var descriptor: FoundationModelCapabilityDescriptor {
        FoundationModelCapabilityDescriptor(
            id: "foundation-models.generate-structured-data",
            displayName: "Generate Structured Data",
            summary: "Generates type-safe structured data using Foundation Models."
        )
    }

    private let provider: any FoundationModelStructuredGenerating

    public init(provider: any FoundationModelStructuredGenerating = FoundationModelsStructuredGenerator()) {
        self.provider = provider
    }

    public func execute(
        _ request: FoundationModelStructuredGenerationRequest<Output>
    ) async throws -> FoundationModelStructuredGenerationResult<Output> {
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FoundationModelsKitError.invalidRequest("Missing prompt")
        }

        return try await provider.generate(Output.self, for: request)
    }
}
