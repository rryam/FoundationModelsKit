import Foundation

public struct FoundationModelStructuredGenerationResult<Output: Sendable>: FoundationModelCapabilityResult, Sendable {
    public let output: Output
    public let metadata: FoundationModelExecutionMetadata

    public init(output: Output, metadata: FoundationModelExecutionMetadata = FoundationModelExecutionMetadata()) {
        self.output = output
        self.metadata = metadata
    }
}
