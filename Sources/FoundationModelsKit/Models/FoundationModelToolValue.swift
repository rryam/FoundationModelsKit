import Foundation
import FoundationModels

/// A provider-neutral JSON value supplied as generated tool arguments.
public enum FoundationModelToolValue: Codable, Equatable, Hashable, Sendable {
    case object([String: FoundationModelToolValue])
    case array([FoundationModelToolValue])
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let values = try? container.decode([Self].self) {
            self = .array(values)
        } else {
            self = .object(try container.decode([String: Self].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    /// Decodes arguments from provider-produced JSON.
    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: jsonData)
    }

    /// Decodes the exact JSON representation produced by Foundation Models.
    public init(generatedContent: GeneratedContent) throws {
        try self.init(jsonData: Data(generatedContent.jsonString.utf8))
    }

    /// Returns deterministic JSON suitable for call identity and replay checks.
    public func canonicalJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
