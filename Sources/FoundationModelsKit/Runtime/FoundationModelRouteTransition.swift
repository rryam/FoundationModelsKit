import Foundation

/// Context supplied before a fallback route prepares a request for a different runtime.
public struct FoundationModelRouteTransition: Sendable, Hashable, Codable {
    public let sourceRuntime: FoundationModelRuntime
    public let destinationRuntime: FoundationModelRuntime
    public let trigger: FoundationModelErrorProjection?

    public init(
        sourceRuntime: FoundationModelRuntime,
        destinationRuntime: FoundationModelRuntime,
        trigger: FoundationModelErrorProjection?
    ) {
        self.sourceRuntime = sourceRuntime
        self.destinationRuntime = destinationRuntime
        self.trigger = trigger
    }
}
