import Foundation

public protocol FoundationModelDynamicSchemaGenerating: Sendable {
    func generate(for request: FoundationModelDynamicSchemaGenerationRequest) async throws -> FoundationModelDynamicSchemaGenerationResult
}
