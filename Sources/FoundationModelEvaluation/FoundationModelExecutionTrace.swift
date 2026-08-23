import Foundation
import FoundationModelsKit

public struct FoundationModelToolCallEvent: Codable, Sendable, Equatable {
    public let name: String
    public let sequence: Int
    public init(name: String, sequence: Int) { self.name = name; self.sequence = sequence }
}

public enum FoundationModelEvaluationOutcome: Codable, Sendable, Equatable {
    case succeeded
    case refused(category: FoundationModelErrorProjection.Category?)
    case failed(projection: FoundationModelErrorProjection?)
}

public struct FoundationModelExecutionTrace: Codable, Sendable, Equatable {
    public let fingerprint: FoundationModelRuntimeFingerprint
    public let toolCalls: [FoundationModelToolCallEvent]
    public let repairCount: Int
    public let durationNanoseconds: UInt64
    public let tokenUsage: ModelTokenUsage?
    public let schemaValid: Bool?
    public let outcome: FoundationModelEvaluationOutcome

    public init(fingerprint: FoundationModelRuntimeFingerprint,
                toolCalls: [FoundationModelToolCallEvent] = [], repairCount: Int = 0,
                durationNanoseconds: UInt64, tokenUsage: ModelTokenUsage? = nil,
                schemaValid: Bool? = nil, outcome: FoundationModelEvaluationOutcome) {
        self.fingerprint = fingerprint
        self.toolCalls = toolCalls
        self.repairCount = repairCount
        self.durationNanoseconds = durationNanoseconds
        self.tokenUsage = tokenUsage
        self.schemaValid = schemaValid
        self.outcome = outcome
    }
}
