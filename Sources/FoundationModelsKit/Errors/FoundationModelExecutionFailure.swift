import Foundation

/// A terminal coordinator failure that preserves both routing evidence and the last provider error.
public struct FoundationModelExecutionFailure: Error, LocalizedError, @unchecked Sendable {
    public let trace: FoundationModelRoutingTrace
    public let underlyingError: (any Error)?

    public init(
        trace: FoundationModelRoutingTrace,
        underlyingError: (any Error)? = nil
    ) {
        self.trace = trace
        self.underlyingError = underlyingError
    }

    public var errorDescription: String? {
        guard let underlyingError else {
            return "No configured Foundation Models runtime could execute the request."
        }
        return "Foundation Models routing failed: \(underlyingError.localizedDescription)"
    }
}
