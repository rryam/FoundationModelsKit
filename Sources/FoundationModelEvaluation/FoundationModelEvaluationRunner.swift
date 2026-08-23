import Foundation
import FoundationModelsKit

public struct FoundationModelEvaluationScenario: Sendable {
    public let toolCalls: [FoundationModelToolCallEvent]
    public let repairCount: Int
    public let tokenUsage: ModelTokenUsage?
    public let schemaValid: Bool?
    public init(toolCalls: [FoundationModelToolCallEvent] = [], repairCount: Int = 0,
                tokenUsage: ModelTokenUsage? = nil, schemaValid: Bool? = nil) {
        self.toolCalls = toolCalls; self.repairCount = repairCount
        self.tokenUsage = tokenUsage; self.schemaValid = schemaValid
    }
}

public struct FoundationModelEvaluationRunner: Sendable {
    public typealias Executor = @Sendable (FoundationModelEvaluationScenario) async throws -> Void
    private let executor: Executor
    public init(executor: @escaping Executor) { self.executor = executor }

    public func run(scenario: FoundationModelEvaluationScenario = .init(),
                    fingerprint: FoundationModelRuntimeFingerprint = .current) async -> FoundationModelExecutionTrace {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            try await executor(scenario)
            return FoundationModelExecutionTrace(fingerprint: fingerprint, toolCalls: scenario.toolCalls,
                repairCount: scenario.repairCount, durationNanoseconds: DispatchTime.now().uptimeNanoseconds - start,
                tokenUsage: scenario.tokenUsage, schemaValid: scenario.schemaValid, outcome: .succeeded)
        } catch {
            return FoundationModelExecutionTrace(fingerprint: fingerprint, toolCalls: scenario.toolCalls,
                repairCount: scenario.repairCount, durationNanoseconds: DispatchTime.now().uptimeNanoseconds - start,
                tokenUsage: scenario.tokenUsage, schemaValid: scenario.schemaValid,
                outcome: .failed(projection: FoundationModelErrorProjection.project(error)))
        }
    }
}
