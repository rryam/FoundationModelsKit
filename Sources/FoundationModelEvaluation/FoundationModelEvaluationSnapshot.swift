import Foundation
import FoundationModelsKit

/// Stable evaluation evidence suitable for a checked-in golden file.
public struct FoundationModelEvaluationSnapshot: Codable, Equatable, Sendable {
    public let fingerprint: FoundationModelRuntimeFingerprint?
    public let toolCallSequence: [FoundationModelToolCallEvent]
    public let repairCount: Int
    public let tokenUsage: ModelTokenUsage?
    public let schemaValid: Bool?
    public let outcome: FoundationModelEvaluationOutcome
    public let refusalOrErrorCategory: FoundationModelErrorProjection.Category?
    public let finalSuccess: Bool

    public init(
        trace: FoundationModelExecutionTrace,
        includeFingerprint: Bool = true
    ) {
        self.fingerprint = includeFingerprint ? trace.fingerprint : nil
        self.toolCallSequence = trace.toolCallSequence
        self.repairCount = trace.repairCount
        self.tokenUsage = trace.tokenUsage
        self.schemaValid = trace.schemaValid
        self.outcome = trace.outcome
        self.refusalOrErrorCategory = trace.refusalOrErrorCategory
        self.finalSuccess = trace.finalSuccess
    }
}
