import Foundation

public protocol FoundationModelCapabilityRequest: Sendable {}

public protocol FoundationModelCapabilityResult: Sendable {}

public struct FoundationModelCapabilityDescriptor: Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let summary: String

    public init(id: String, displayName: String, summary: String) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
    }
}

/// A task-oriented use case that can be shared by the app, App Intents, and CLI adapters.
public protocol FoundationModelCapabilityUseCase: Sendable {
    associatedtype Request: FoundationModelCapabilityRequest
    associatedtype Result: FoundationModelCapabilityResult

    static var descriptor: FoundationModelCapabilityDescriptor { get }

    func execute(_ request: Request) async throws -> Result
}
