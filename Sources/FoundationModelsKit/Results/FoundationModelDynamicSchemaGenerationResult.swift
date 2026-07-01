import Foundation
import FoundationModels

public struct FoundationModelDynamicSchemaGenerationResult: FoundationModelCapabilityResult, Sendable {
    public let output: GeneratedContent
    public let metadata: FoundationModelExecutionMetadata

    public init(
        output: GeneratedContent,
        metadata: FoundationModelExecutionMetadata = FoundationModelExecutionMetadata()
    ) {
        self.output = output
        self.metadata = metadata
    }
}
