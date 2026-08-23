import Foundation

/// One runtime mismatch between generated tool arguments and the tool's declared schema.
public struct FoundationModelToolArgumentIssue: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Equatable, Sendable {
        case typeMismatch
        case missingRequiredProperty
        case additionalProperty
        case enumMismatch
        case numberBelowMinimum
        case numberAboveMaximum
        case arrayTooShort
        case arrayTooLong
        case anyOfMismatch
        case missingDiscriminator
        case invalidDiscriminator
        case ambiguousDiscriminator
        case invalidJSONNumber
        case invalidIdempotencyKey
        case idempotencyKeyConflict
    }

    public let code: Code
    public let path: String
    public let message: String

    public init(code: Code, path: String, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}
