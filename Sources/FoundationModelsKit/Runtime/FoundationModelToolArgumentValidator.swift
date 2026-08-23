import Foundation

/// Validates provider-produced JSON values against a tool argument schema.
public struct FoundationModelToolArgumentValidator: Sendable {
    public init() {}

    public func issues(
        in value: FoundationModelToolValue,
        against schema: FoundationModelToolSchema
    ) -> [FoundationModelToolArgumentIssue] {
        validate(value, against: schema, at: "$", includingUnion: true)
    }

    private func validate(
        _ value: FoundationModelToolValue,
        against schema: FoundationModelToolSchema,
        at path: String,
        includingUnion: Bool
    ) -> [FoundationModelToolArgumentIssue] {
        var issues: [FoundationModelToolArgumentIssue] = []

        if let type = schema.type, !value.matches(type) {
            return [issue(
                .typeMismatch,
                at: path,
                "Expected \(type.rawValue), received \(value.typeDescription)."
            )]
        }

        if case .number(let number) = value, !number.isFinite {
            issues.append(issue(.invalidJSONNumber, at: path, "JSON numbers must be finite."))
        }

        if let enumValues = schema.enumValues, !enumValues.contains(value) {
            issues.append(issue(.enumMismatch, at: path, "Value is not one of the declared enum values."))
        }

        switch value {
        case .object(let object):
            issues.append(contentsOf: validateObject(object, against: schema, at: path))
        case .array(let array):
            issues.append(contentsOf: validateArray(array, against: schema, at: path))
        case .number(let number):
            issues.append(contentsOf: validateNumber(number, against: schema, at: path))
        case .string, .boolean, .null:
            break
        }

        if includingUnion, let branches = schema.anyOf {
            issues.append(contentsOf: validateUnion(value, branches: branches, schema: schema, at: path))
        }

        return issues
    }

    private func validateObject(
        _ object: [String: FoundationModelToolValue],
        against schema: FoundationModelToolSchema,
        at path: String
    ) -> [FoundationModelToolArgumentIssue] {
        var issues: [FoundationModelToolArgumentIssue] = []

        for name in schema.required.sorted() where object[name] == nil {
            issues.append(issue(
                .missingRequiredProperty,
                at: appending(name, to: path),
                "Required property '\(name)' is missing."
            ))
        }

        let properties = schema.properties ?? [:]
        let unionPropertyNames = schema.anyOf?.reduce(into: Set<String>()) { names, branch in
            names.formUnion(branch.properties?.keys.map { $0 } ?? [])
        } ?? []
        let declaredPropertyNames = Set(properties.keys).union(unionPropertyNames)
        if !schema.additionalProperties {
            for name in object.keys.sorted() where !declaredPropertyNames.contains(name) {
                issues.append(issue(
                    .additionalProperty,
                    at: appending(name, to: path),
                    "Property '\(name)' is not declared by the tool schema."
                ))
            }
        }

        for name in properties.keys.sorted() {
            guard let childValue = object[name], let childSchema = properties[name] else {
                continue
            }
            issues.append(contentsOf: validate(
                childValue,
                against: childSchema,
                at: appending(name, to: path),
                includingUnion: true
            ))
        }

        return issues
    }

    private func validateArray(
        _ array: [FoundationModelToolValue],
        against schema: FoundationModelToolSchema,
        at path: String
    ) -> [FoundationModelToolArgumentIssue] {
        var issues: [FoundationModelToolArgumentIssue] = []

        if let minimumItems = schema.minimumItems, array.count < minimumItems {
            issues.append(issue(
                .arrayTooShort,
                at: path,
                "Array contains \(array.count) items; minimum is \(minimumItems)."
            ))
        }
        if let maximumItems = schema.maximumItems, array.count > maximumItems {
            issues.append(issue(
                .arrayTooLong,
                at: path,
                "Array contains \(array.count) items; maximum is \(maximumItems)."
            ))
        }
        if let itemSchema = schema.items {
            for (index, item) in array.enumerated() {
                issues.append(contentsOf: validate(
                    item,
                    against: itemSchema,
                    at: "\(path)[\(index)]",
                    includingUnion: true
                ))
            }
        }

        return issues
    }

    private func validateNumber(
        _ number: Double,
        against schema: FoundationModelToolSchema,
        at path: String
    ) -> [FoundationModelToolArgumentIssue] {
        var issues: [FoundationModelToolArgumentIssue] = []

        if let minimum = schema.minimum, number < minimum {
            issues.append(issue(
                .numberBelowMinimum,
                at: path,
                "Number \(number) is below the minimum \(minimum)."
            ))
        }
        if let maximum = schema.maximum, number > maximum {
            issues.append(issue(
                .numberAboveMaximum,
                at: path,
                "Number \(number) is above the maximum \(maximum)."
            ))
        }

        return issues
    }

    private func validateUnion(
        _ value: FoundationModelToolValue,
        branches: [FoundationModelToolSchema],
        schema: FoundationModelToolSchema,
        at path: String
    ) -> [FoundationModelToolArgumentIssue] {
        guard let discriminator = schema.discriminator else {
            let hasMatch = branches.contains { branch in
                validate(value, against: branch, at: path, includingUnion: true).isEmpty
            }
            return hasMatch ? [] : [issue(
                .anyOfMismatch,
                at: path,
                "Value does not match any declared schema branch."
            )]
        }

        guard case .object(let object) = value else {
            return [issue(
                .typeMismatch,
                at: path,
                "A discriminated union requires an object value."
            )]
        }
        let discriminatorPath = appending(discriminator.propertyName, to: path)
        guard let discriminatorValue = object[discriminator.propertyName] else {
            return [issue(
                .missingDiscriminator,
                at: discriminatorPath,
                "Discriminator '\(discriminator.propertyName)' is missing."
            )]
        }

        let matchingBranches = branches.filter { branch in
            guard branch.required.contains(discriminator.propertyName),
                  let values = branch.properties?[discriminator.propertyName]?.enumValues else {
                return false
            }
            return values.contains(discriminatorValue)
        }

        guard !matchingBranches.isEmpty else {
            return [issue(
                .invalidDiscriminator,
                at: discriminatorPath,
                "Discriminator does not select a declared schema branch."
            )]
        }
        guard matchingBranches.count == 1, let branch = matchingBranches.first else {
            return [issue(
                .ambiguousDiscriminator,
                at: discriminatorPath,
                "Discriminator selects more than one schema branch."
            )]
        }

        return validate(value, against: branch, at: path, includingUnion: true)
    }

    private func issue(
        _ code: FoundationModelToolArgumentIssue.Code,
        at path: String,
        _ message: String
    ) -> FoundationModelToolArgumentIssue {
        FoundationModelToolArgumentIssue(code: code, path: path, message: message)
    }

    private func appending(_ component: String, to path: String) -> String {
        let isIdentifier = component.first?.isLetter == true
            && component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        if isIdentifier {
            return "\(path).\(component)"
        }
        let escaped = component
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\(path)[\"\(escaped)\"]"
    }
}

private extension FoundationModelToolValue {
    func matches(_ type: FoundationModelToolSchema.ValueType) -> Bool {
        switch (type, self) {
        case (.object, .object), (.array, .array), (.string, .string),
             (.number, .number), (.boolean, .boolean):
            return true
        case (.integer, .number(let number)):
            return number.isFinite && number.rounded(.towardZero) == number
        default:
            return false
        }
    }

    var typeDescription: String {
        switch self {
        case .object: "object"
        case .array: "array"
        case .string: "string"
        case .number: "number"
        case .boolean: "boolean"
        case .null: "null"
        }
    }
}
