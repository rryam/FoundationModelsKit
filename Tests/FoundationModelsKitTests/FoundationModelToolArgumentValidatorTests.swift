import Foundation
import FoundationModels
import Testing
@testable import FoundationModelsKit

@Suite("Tool argument validator")
struct ToolArgumentValidatorTests {
    private let validator = FoundationModelToolArgumentValidator()

    @Test("Required fields, integers, ranges, arrays, and enums are enforced")
    func validatesCoreConstraints() {
        let schema = FoundationModelToolSchema(
            type: .object,
            properties: [
                "count": FoundationModelToolSchema(type: .integer, minimum: 1, maximum: 3),
                "mode": FoundationModelToolSchema(
                    type: .string,
                    enumValues: [.string("fast"), .string("safe")]
                ),
                "tags": FoundationModelToolSchema(
                    type: .array,
                    items: FoundationModelToolSchema(type: .string),
                    minimumItems: 1,
                    maximumItems: 2
                )
            ],
            required: ["count", "mode", "tags"]
        )

        let issues = validator.issues(
            in: .object([
                "count": .number(2.5),
                "mode": .string("turbo"),
                "tags": .array([]),
                "extra": .boolean(true)
            ]),
            against: schema
        )

        #expect(issues.map(\.code).contains(.typeMismatch))
        #expect(issues.map(\.code).contains(.enumMismatch))
        #expect(issues.map(\.code).contains(.arrayTooShort))
        #expect(issues.map(\.code).contains(.additionalProperty))
    }

    @Test("Missing required fields report the missing field path")
    func reportsMissingRequiredPath() throws {
        let schema = FoundationModelToolSchema(
            type: .object,
            properties: ["query": FoundationModelToolSchema(type: .string)],
            required: ["query"]
        )

        let issue = try #require(validator.issues(in: .object([:]), against: schema).first)

        #expect(issue.code == .missingRequiredProperty)
        #expect(issue.path == "$.query")
    }

    @Test("anyOf accepts any matching branch")
    func validatesAnyOf() {
        let schema = FoundationModelToolSchema(anyOf: [
            FoundationModelToolSchema(type: .string),
            FoundationModelToolSchema(type: .integer)
        ])

        #expect(validator.issues(in: .string("value"), against: schema).isEmpty)
        #expect(validator.issues(in: .number(2), against: schema).isEmpty)
        #expect(validator.issues(in: .boolean(true), against: schema).map(\.code) == [.anyOfMismatch])
    }

    @Test("Foundation Models generated content bridges through its JSON representation")
    func bridgesGeneratedContent() throws {
        let content = GeneratedContent(properties: [
            "query": "Swift",
            "limit": 3
        ])

        let value = try FoundationModelToolValue(generatedContent: content)

        #expect(value == .object([
            "query": .string("Swift"),
            "limit": .number(3)
        ]))
    }

    @Test("Discriminated unions select and validate exactly one branch")
    func validatesDiscriminatedUnion() {
        let searchBranch = branch(kind: "search", valueType: .string)
        let nearbyBranch = branch(kind: "nearby", valueType: .integer)
        let schema = FoundationModelToolSchema(
            type: .object,
            anyOf: [searchBranch, nearbyBranch],
            discriminator: .init(propertyName: "kind")
        )

        let valid = FoundationModelToolValue.object([
            "kind": .string("search"),
            "value": .string("Swift")
        ])
        let wrongBranchValue = FoundationModelToolValue.object([
            "kind": .string("nearby"),
            "value": .string("not an integer")
        ])
        let unknownDiscriminator = FoundationModelToolValue.object([
            "kind": .string("unknown"),
            "value": .string("Swift")
        ])

        #expect(validator.issues(in: valid, against: schema).isEmpty)
        #expect(validator.issues(in: wrongBranchValue, against: schema).map(\.code).contains(.typeMismatch))
        #expect(validator.issues(in: unknownDiscriminator, against: schema).map(\.code) == [.invalidDiscriminator])
    }

    @Test("Tool schemas decode standard JSON Schema keyword names")
    func decodesJSONSchemaKeywords() throws {
        let data = Data("""
        {
          "type": "array",
          "items": { "type": "number", "minimum": 1, "maximum": 4 },
          "minItems": 1,
          "maxItems": 2
        }
        """.utf8)

        let schema = try JSONDecoder().decode(FoundationModelToolSchema.self, from: data)

        #expect(schema.type == .array)
        #expect(schema.minimumItems == 1)
        #expect(schema.maximumItems == 2)
        #expect(schema.items?.minimum == 1)
        #expect(schema.items?.maximum == 4)
    }

    private func branch(
        kind: String,
        valueType: FoundationModelToolSchema.ValueType
    ) -> FoundationModelToolSchema {
        FoundationModelToolSchema(
            type: .object,
            properties: [
                "kind": FoundationModelToolSchema(
                    type: .string,
                    enumValues: [.string(kind)]
                ),
                "value": FoundationModelToolSchema(type: valueType)
            ],
            required: ["kind", "value"]
        )
    }
}
