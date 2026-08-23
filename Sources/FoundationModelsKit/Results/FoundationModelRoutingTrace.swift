import Foundation

/// A privacy-safe record of runtime attempts and fallback decisions for one request.
public struct FoundationModelRoutingTrace: Sendable, Hashable, Codable {
    public enum AttemptOutcome: String, Sendable, Hashable, Codable {
        case succeeded
        case failed
        case skippedOpenCircuit
        case preparationFailed
    }

    public enum StopReason: String, Sendable, Hashable, Codable {
        case circuitOpen
        case failureNotRetryable
        case mayHaveSideEffects
        case noFallback
        case preparationFailed
    }

    public enum RetryDecision: Sendable, Hashable, Codable {
        case notNeeded
        case useFallback(FoundationModelRuntime)
        case stop(StopReason)
    }

    public struct Attempt: Sendable, Hashable, Codable {
        public let runtime: FoundationModelRuntime
        public let startedAt: Date
        public let finishedAt: Date
        public let circuitPhase: FoundationModelCircuitState.Phase?
        public let outcome: AttemptOutcome
        public let failure: FoundationModelErrorProjection?
        public let errorType: String?
        public let nextProbeAt: Date?
        public let cooldown: TimeInterval?
        public let retryDecision: RetryDecision

        public init(
            runtime: FoundationModelRuntime,
            startedAt: Date,
            finishedAt: Date,
            circuitPhase: FoundationModelCircuitState.Phase? = nil,
            outcome: AttemptOutcome,
            failure: FoundationModelErrorProjection? = nil,
            errorType: String? = nil,
            nextProbeAt: Date? = nil,
            cooldown: TimeInterval? = nil,
            retryDecision: RetryDecision
        ) {
            self.runtime = runtime
            self.startedAt = startedAt
            self.finishedAt = finishedAt
            self.circuitPhase = circuitPhase
            self.outcome = outcome
            self.failure = failure
            self.errorType = errorType
            self.nextProbeAt = nextProbeAt
            self.cooldown = cooldown
            self.retryDecision = retryDecision
        }
    }

    public let correlationID: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let attempts: [Attempt]
    public let selectedRuntime: FoundationModelRuntime?

    public init(
        correlationID: UUID,
        startedAt: Date,
        finishedAt: Date,
        attempts: [Attempt],
        selectedRuntime: FoundationModelRuntime?
    ) {
        self.correlationID = correlationID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.attempts = attempts
        self.selectedRuntime = selectedRuntime
    }
}
