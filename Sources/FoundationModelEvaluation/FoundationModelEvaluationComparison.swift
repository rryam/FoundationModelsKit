import Foundation

/// Exact field differences between expected and observed evaluation snapshots.
public struct FoundationModelEvaluationComparison: Codable, Equatable, Sendable {
    public enum Field: String, Codable, CaseIterable, Equatable, Sendable {
        case fingerprint
        case toolCallSequence = "tool_call_sequence"
        case repairCount = "repair_count"
        case tokenUsage = "token_usage"
        case schemaValid = "schema_valid"
        case outcome
        case refusalOrErrorCategory = "refusal_or_error_category"
        case finalSuccess = "final_success"
    }

    public let mismatchedFields: [Field]

    public var passed: Bool {
        mismatchedFields.isEmpty
    }

    public init(
        expected: FoundationModelEvaluationSnapshot,
        actual: FoundationModelEvaluationSnapshot
    ) {
        var fields: [Field] = []
        if expected.fingerprint != actual.fingerprint { fields.append(.fingerprint) }
        if expected.toolCallSequence != actual.toolCallSequence { fields.append(.toolCallSequence) }
        if expected.repairCount != actual.repairCount { fields.append(.repairCount) }
        if expected.tokenUsage != actual.tokenUsage { fields.append(.tokenUsage) }
        if expected.schemaValid != actual.schemaValid { fields.append(.schemaValid) }
        if expected.outcome != actual.outcome { fields.append(.outcome) }
        if expected.refusalOrErrorCategory != actual.refusalOrErrorCategory {
            fields.append(.refusalOrErrorCategory)
        }
        if expected.finalSuccess != actual.finalSuccess { fields.append(.finalSuccess) }
        self.mismatchedFields = fields
    }
}
