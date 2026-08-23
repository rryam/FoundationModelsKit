import Foundation
import FoundationModelsKit

/// Measures app-owned Foundation Models scenarios and normalizes their terminal evidence.
public struct FoundationModelEvaluationRunner: Sendable {
    public typealias ErrorProjector = @Sendable (any Error) -> FoundationModelErrorProjection?
    public typealias Operation = @Sendable () async throws -> FoundationModelEvaluationObservation

    private let errorProjector: ErrorProjector

    public init(
        errorProjector: @escaping ErrorProjector = FoundationModelErrorProjection.project
    ) {
        self.errorProjector = errorProjector
    }

    /// Runs one scenario. Prompt and response text remain app-owned and are not captured.
    public func run(
        fingerprint: FoundationModelRuntimeFingerprint = .current,
        operation: @escaping Operation
    ) async -> FoundationModelExecutionTrace {
        let startedAt = Date()
        let clock = ContinuousClock()
        let startedInstant = clock.now

        do {
            let observation = try await operation()
            let finishedAt = Date()
            return FoundationModelExecutionTrace(
                startedAt: startedAt,
                finishedAt: finishedAt,
                fingerprint: fingerprint,
                toolCallSequence: observation.toolCallSequence,
                repairCount: observation.repairCount,
                latency: FoundationModelLatency(
                    total: Self.seconds(clock.now - startedInstant),
                    timeToFirstToken: observation.timeToFirstToken
                ),
                tokenUsage: observation.tokenUsage,
                schemaValid: observation.schemaValid,
                outcome: .completed,
                finalSuccess: observation.finalSuccess
            )
        } catch is CancellationError {
            let finishedAt = Date()
            return FoundationModelExecutionTrace(
                startedAt: startedAt,
                finishedAt: finishedAt,
                fingerprint: fingerprint,
                latency: FoundationModelLatency(total: Self.seconds(clock.now - startedInstant)),
                outcome: .cancelled,
                finalSuccess: false
            )
        } catch {
            let finishedAt = Date()
            let projection = errorProjector(error)
            let category = projection?.category
            let wasRefused = category == .refusal || category == .guardrailViolation
            return FoundationModelExecutionTrace(
                startedAt: startedAt,
                finishedAt: finishedAt,
                fingerprint: fingerprint,
                latency: FoundationModelLatency(total: Self.seconds(clock.now - startedInstant)),
                outcome: wasRefused ? .refused : .failed,
                refusalOrErrorCategory: category,
                finalSuccess: false
            )
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
