import Foundation

public enum FoundationModelInvocationSource: String, Sendable, Hashable, Codable {
    case app
    case appIntent
    case cli
    case automation
    case unknown
}

public struct FoundationModelInvocationContext: Sendable, Hashable, Codable {
    public let source: FoundationModelInvocationSource
    public let localeIdentifier: String?
    public let correlationID: UUID

    public init(
        source: FoundationModelInvocationSource,
        localeIdentifier: String? = nil,
        correlationID: UUID = UUID()
    ) {
        self.source = source
        self.localeIdentifier = localeIdentifier
        self.correlationID = correlationID
    }
}
