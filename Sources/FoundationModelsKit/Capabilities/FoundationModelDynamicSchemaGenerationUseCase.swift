import Foundation

public struct FoundationModelDynamicSchemaGenerationUseCase: FoundationModelCapabilityUseCase {
    public static let descriptor = FoundationModelCapabilityDescriptor(
        id: "foundation-models.generate-dynamic-schema",
        displayName: "Generate Dynamic Schema Content",
        summary: "Generates content using a runtime-defined generation schema."
    )

    private let provider: any FoundationModelDynamicSchemaGenerating

    public init(provider: any FoundationModelDynamicSchemaGenerating = FoundationModelsDynamicSchemaGenerator()) {
        self.provider = provider
    }

    public func execute(
        _ request: FoundationModelDynamicSchemaGenerationRequest
    ) async throws -> FoundationModelDynamicSchemaGenerationResult {
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FoundationModelsKitError.invalidRequest("Missing prompt")
        }

        return try await provider.generate(for: request)
    }
}
