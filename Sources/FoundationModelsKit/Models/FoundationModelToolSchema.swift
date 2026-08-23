import Foundation

/// A provider-neutral schema used to validate generated tool arguments before execution.
public final class FoundationModelToolSchema: Codable, Equatable, Sendable {
    public enum ValueType: String, Codable, Equatable, Sendable {
        case object
        case array
        case string
        case integer
        case number
        case boolean
    }

    /// Selects one `anyOf` branch using a required property whose branch schema has an enum value.
    public struct Discriminator: Codable, Equatable, Sendable {
        public let propertyName: String

        public init(propertyName: String) {
            self.propertyName = propertyName
        }
    }

    public let type: ValueType?
    public let properties: [String: FoundationModelToolSchema]?
    public let required: [String]
    public let additionalProperties: Bool
    public let items: FoundationModelToolSchema?
    public let minimumItems: Int?
    public let maximumItems: Int?
    public let enumValues: [FoundationModelToolValue]?
    public let anyOf: [FoundationModelToolSchema]?
    public let discriminator: Discriminator?
    public let minimum: Double?
    public let maximum: Double?

    public init(
        type: ValueType? = nil,
        properties: [String: FoundationModelToolSchema]? = nil,
        required: [String] = [],
        additionalProperties: Bool = false,
        items: FoundationModelToolSchema? = nil,
        minimumItems: Int? = nil,
        maximumItems: Int? = nil,
        enumValues: [FoundationModelToolValue]? = nil,
        anyOf: [FoundationModelToolSchema]? = nil,
        discriminator: Discriminator? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
        self.items = items
        self.minimumItems = minimumItems
        self.maximumItems = maximumItems
        self.enumValues = enumValues
        self.anyOf = anyOf
        self.discriminator = discriminator
        self.minimum = minimum
        self.maximum = maximum
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(ValueType.self, forKey: .type)
        properties = try container.decodeIfPresent(
            [String: FoundationModelToolSchema].self,
            forKey: .properties
        )
        required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
        additionalProperties = try container.decodeIfPresent(
            Bool.self,
            forKey: .additionalProperties
        ) ?? false
        items = try container.decodeIfPresent(FoundationModelToolSchema.self, forKey: .items)
        minimumItems = try container.decodeIfPresent(Int.self, forKey: .minimumItems)
        maximumItems = try container.decodeIfPresent(Int.self, forKey: .maximumItems)
        enumValues = try container.decodeIfPresent(
            [FoundationModelToolValue].self,
            forKey: .enumValues
        )
        anyOf = try container.decodeIfPresent([FoundationModelToolSchema].self, forKey: .anyOf)
        discriminator = try container.decodeIfPresent(Discriminator.self, forKey: .discriminator)
        minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(properties, forKey: .properties)
        if !required.isEmpty {
            try container.encode(required, forKey: .required)
        }
        if additionalProperties {
            try container.encode(true, forKey: .additionalProperties)
        }
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(minimumItems, forKey: .minimumItems)
        try container.encodeIfPresent(maximumItems, forKey: .maximumItems)
        try container.encodeIfPresent(enumValues, forKey: .enumValues)
        try container.encodeIfPresent(anyOf, forKey: .anyOf)
        try container.encodeIfPresent(discriminator, forKey: .discriminator)
        try container.encodeIfPresent(minimum, forKey: .minimum)
        try container.encodeIfPresent(maximum, forKey: .maximum)
    }

    /// Bridges the JSON Schema subset already supported by FoundationModelsKit.
    public convenience init(jsonSchema: FoundationModelsJSONSchema) throws {
        try jsonSchema.validate()
        let properties = try jsonSchema.properties.map { properties in
            try Dictionary(uniqueKeysWithValues: properties.map { name, schema in
                (name, try FoundationModelToolSchema(jsonSchema: schema))
            })
        }
        let items = try jsonSchema.items.map(FoundationModelToolSchema.init(jsonSchema:))
        let type = try jsonSchema.resolvedType()

        self.init(
            type: ValueType(rawValue: type.rawValue),
            properties: properties,
            required: jsonSchema.required ?? [],
            additionalProperties: jsonSchema.additionalProperties ?? false,
            items: items,
            minimumItems: jsonSchema.minimumItems,
            maximumItems: jsonSchema.maximumItems,
            enumValues: jsonSchema.enumValues?.map(FoundationModelToolValue.string)
        )
    }

    public static func == (lhs: FoundationModelToolSchema, rhs: FoundationModelToolSchema) -> Bool {
        lhs.type == rhs.type
            && lhs.properties == rhs.properties
            && lhs.required == rhs.required
            && lhs.additionalProperties == rhs.additionalProperties
            && lhs.items == rhs.items
            && lhs.minimumItems == rhs.minimumItems
            && lhs.maximumItems == rhs.maximumItems
            && lhs.enumValues == rhs.enumValues
            && lhs.anyOf == rhs.anyOf
            && lhs.discriminator == rhs.discriminator
            && lhs.minimum == rhs.minimum
            && lhs.maximum == rhs.maximum
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case additionalProperties
        case items
        case minimumItems = "minItems"
        case maximumItems = "maxItems"
        case enumValues = "enum"
        case anyOf
        case discriminator
        case minimum
        case maximum
    }
}
