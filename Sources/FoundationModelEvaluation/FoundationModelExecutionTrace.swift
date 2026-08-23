import Foundation
import FoundationModelsKit

/// Reproducible, privacy-safe evidence for one Foundation Models evaluation run.
public struct FoundationModelExecutionTrace: Codable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let fingerprint: FoundationModelRuntimeFingerprint
    public let toolCallSequence: [FoundationModelToolCallEvent]
    public let repairCount: Int
    public let latency: FoundationModelLatency
    public let tokenUsage: ModelTokenUsage?
    public let schemaValid: Bool?
    public let outcome: FoundationModelEvaluationOutcome
    public let refusalOrErrorCategory: FoundationModelErrorProjection.Category?
    public let finalSuccess: Bool

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        fingerprint: FoundationModelRuntimeFingerprint,
        toolCallSequence: [FoundationModelToolCallEvent] = [],
        repairCount: Int = 0,
        latency: FoundationModelLatency,
        tokenUsage: ModelTokenUsage? = nil,
        schemaValid: Bool? = nil,
        outcome: FoundationModelEvaluationOutcome,
        refusalOrErrorCategory: FoundationModelErrorProjection.Category? = nil,
        finalSuccess: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = max(startedAt, finishedAt)
        self.fingerprint = fingerprint
        self.toolCallSequence = toolCallSequence.sorted { $0.sequence < $1.sequence }
        self.repairCount = max(0, repairCount)
        self.latency = latency
        self.tokenUsage = tokenUsage
        self.schemaValid = schemaValid
        self.outcome = outcome
        self.refusalOrErrorCategory = refusalOrErrorCategory
        self.finalSuccess = finalSuccess
    }
}
