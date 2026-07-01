import Foundation

public struct FoundationModelTextGenerationResult: FoundationModelCapabilityResult, Sendable, Hashable {
    public let content: String
    public let metadata: FoundationModelExecutionMetadata

    public init(content: String, metadata: FoundationModelExecutionMetadata = FoundationModelExecutionMetadata()) {
        self.content = content
        self.metadata = metadata
    }
}
