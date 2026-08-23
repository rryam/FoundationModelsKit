import Foundation

/// The successful output and routing evidence produced by an execution coordinator.
public struct FoundationModelRoutedResult<Output: Sendable>: Sendable {
    public let output: Output
    public let trace: FoundationModelRoutingTrace

    public init(output: Output, trace: FoundationModelRoutingTrace) {
        self.output = output
        self.trace = trace
    }
}
