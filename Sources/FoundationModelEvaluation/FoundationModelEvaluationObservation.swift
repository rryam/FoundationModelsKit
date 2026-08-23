import Foundation
import FoundationModelsKit

/// Metrics captured by app-owned execution code and returned to the evaluation runner.
public struct FoundationModelEvaluationObservation: Equatable, Sendable {
    public let toolCallSequence: [FoundationModelToolCallEvent]
    public let repairCount: Int
    public let timeToFirstToken: TimeInterval?
    public let tokenUsage: ModelTokenUsage?
    public let schemaValid: Bool?
    public let finalSuccess: Bool

    public init(
        toolCallSequence: [FoundationModelToolCallEvent] = [],
        repairCount: Int = 0,
        timeToFirstToken: TimeInterval? = nil,
        tokenUsage: ModelTokenUsage? = nil,
        schemaValid: Bool? = nil,
        finalSuccess: Bool = true
    ) {
        self.toolCallSequence = toolCallSequence.sorted { $0.sequence < $1.sequence }
        self.repairCount = max(0, repairCount)
        self.timeToFirstToken = timeToFirstToken.map { max(0, $0) }
        self.tokenUsage = tokenUsage
        self.schemaValid = schemaValid
        self.finalSuccess = finalSuccess && schemaValid != false
    }
}
