import Foundation

private enum FoundationModelTimedToolResult<Output: Sendable>: Sendable {
    case output(Output)
    case deadlineReached
}

/// Validates and supervises model-directed tool calls for one turn.
public actor FoundationModelToolExecutionPolicy {
    public typealias OutputTokenEstimator<Output: Sendable> = @Sendable (Output) async throws -> Int

    private struct CallIdentity: Hashable, Sendable {
        let toolName: String
        let canonicalArguments: Data
    }

    private let budget: FoundationModelToolExecutionBudget
    private let validator: FoundationModelToolArgumentValidator
    private let elapsedTime: @Sendable () -> Duration

    private var callCount = 0
    private var repairCount = 0
    private var seenCalls: Set<CallIdentity> = []
    private var reservedIdempotencyKeys: [String: CallIdentity] = [:]

    public init(
        budget: FoundationModelToolExecutionBudget = FoundationModelToolExecutionBudget(),
        validator: FoundationModelToolArgumentValidator = FoundationModelToolArgumentValidator()
    ) {
        let clock = ContinuousClock()
        let startedAt = clock.now
        self.budget = budget
        self.validator = validator
        self.elapsedTime = { clock.now - startedAt }
    }

    init(
        budget: FoundationModelToolExecutionBudget,
        validator: FoundationModelToolArgumentValidator = FoundationModelToolArgumentValidator(),
        elapsedTime: @escaping @Sendable () -> Duration
    ) {
        self.budget = budget
        self.validator = validator
        self.elapsedTime = elapsedTime
    }

    /// Returns the call and repair usage accumulated by this per-turn policy.
    public func usage() -> FoundationModelToolExecutionUsage {
        FoundationModelToolExecutionUsage(
            callCount: callCount,
            repairCount: repairCount,
            elapsed: elapsedTime()
        )
    }

    /// Validates, authorizes, and executes one generated tool call.
    ///
    /// Policy rejections are returned as typed results. Errors thrown by app-owned confirmation,
    /// token estimation, or tool code remain authoritative and are propagated without retry.
    public func execute<Output: Sendable>(
        tool toolName: String,
        arguments: FoundationModelToolValue,
        schema: FoundationModelToolSchema,
        attempt: FoundationModelToolExecutionAttempt = .initial,
        effect: FoundationModelToolEffect = .readOnly,
        authorizer: (any FoundationModelToolExecutionAuthorizing)? = nil,
        confirmer: (any FoundationModelToolExecutionConfirming)? = nil,
        outputTokenEstimator: OutputTokenEstimator<Output>? = nil,
        operation: @escaping @Sendable () async throws -> Output
    ) async throws -> FoundationModelToolExecutionResult<Output> {
        try Task.checkCancellation()

        if let exceeded = admissionBudgetExceeded(for: attempt) {
            return .budgetExceeded(exceeded)
        }

        guard let canonicalArguments = try? arguments.canonicalJSONData() else {
            return .invalidArguments([
                FoundationModelToolArgumentIssue(
                    code: .invalidJSONNumber,
                    path: "$",
                    message: "Arguments cannot be represented as JSON."
                )
            ])
        }

        callCount += 1
        if attempt == .repair {
            repairCount += 1
        }

        let identity = CallIdentity(toolName: toolName, canonicalArguments: canonicalArguments)
        let callFingerprint = Self.fingerprint(for: identity)
        guard seenCalls.insert(identity).inserted else {
            return .loopDetected(FoundationModelToolLoop(
                toolName: toolName,
                callFingerprint: callFingerprint
            ))
        }

        let issues = validator.issues(in: arguments, against: schema)
        guard issues.isEmpty else {
            return .invalidArguments(issues)
        }

        if let maxOutputTokens = budget.maxOutputTokens, outputTokenEstimator == nil {
            return .budgetExceeded(.outputTokenEstimatorRequired(limit: maxOutputTokens))
        }

        switch effect {
        case .readOnly:
            break
        case .sideEffect(.confirmation):
            if let denial = try await authorizationDenial(
                for: identity,
                callFingerprint: callFingerprint,
                phase: .beforeConfirmation,
                authorizer: authorizer,
                arguments: arguments
            ) {
                return .authorizationDenied(denial)
            }
            let request = FoundationModelToolConfirmationRequest(
                toolName: toolName,
                callFingerprint: callFingerprint
            )
            guard let confirmer, await confirmer.confirm(request, arguments: arguments) else {
                releasePendingConfirmation(identity, attempt: attempt)
                return .confirmationRequired(request)
            }
        case .sideEffect(.idempotency(let key)):
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else {
                return .invalidArguments([
                    FoundationModelToolArgumentIssue(
                        code: .invalidIdempotencyKey,
                        path: "$",
                        message: "A side-effecting tool requires a nonempty idempotency key."
                    )
                ])
            }

            let scopedKey = "\(toolName)\u{0}\(normalizedKey)"
            if let priorIdentity = reservedIdempotencyKeys[scopedKey], priorIdentity != identity {
                return .invalidArguments([
                    FoundationModelToolArgumentIssue(
                        code: .idempotencyKeyConflict,
                        path: "$",
                        message: "The idempotency key is already reserved for different arguments."
                    )
                ])
            }
            reservedIdempotencyKeys[scopedKey] = identity
        }

        if let denial = try await authorizationDenial(
            for: identity,
            callFingerprint: callFingerprint,
            phase: .beforeExecution,
            authorizer: authorizer,
            arguments: arguments
        ) {
            return .authorizationDenied(denial)
        }

        try Task.checkCancellation()
        if let exceeded = durationBudgetExceeded() {
            return .budgetExceeded(exceeded)
        }

        let operationResult = try await raceAgainstDuration(operation)
        guard case .output(let output) = operationResult else {
            return .budgetExceeded(.duration(limit: budget.maxDuration ?? .zero))
        }
        try Task.checkCancellation()

        if let exceeded = durationBudgetExceeded() {
            return .budgetExceeded(exceeded)
        }

        let outputTokenCount: Int?
        if let outputTokenEstimator {
            let estimationResult = try await raceAgainstDuration {
                try await outputTokenEstimator(output)
            }
            guard case .output(let estimatedTokens) = estimationResult else {
                return .budgetExceeded(.duration(limit: budget.maxDuration ?? .zero))
            }
            outputTokenCount = max(0, estimatedTokens)
        } else {
            outputTokenCount = nil
        }

        if let exceeded = durationBudgetExceeded() {
            return .budgetExceeded(exceeded)
        }
        if let limit = budget.maxOutputTokens,
           let outputTokenCount,
           outputTokenCount > limit {
            return .budgetExceeded(.outputTokens(limit: limit, actual: outputTokenCount))
        }

        return .succeeded(output, usage: usage(), outputTokenCount: outputTokenCount)
    }

    private func authorizationDenial(
        for identity: CallIdentity,
        callFingerprint: String,
        phase: FoundationModelToolAuthorizationPhase,
        authorizer: (any FoundationModelToolExecutionAuthorizing)?,
        arguments: FoundationModelToolValue
    ) async throws -> FoundationModelToolAuthorizationDenial? {
        guard let authorizer else {
            return nil
        }

        let request = FoundationModelToolAuthorizationRequest(
            toolName: identity.toolName,
            callFingerprint: callFingerprint,
            phase: phase
        )
        let decision = await authorizer.authorize(request, arguments: arguments)
        try Task.checkCancellation()

        switch decision {
        case .allowed:
            return nil
        case .denied(let denial):
            return denial
        }
    }

    private func releasePendingConfirmation(
        _ identity: CallIdentity,
        attempt: FoundationModelToolExecutionAttempt
    ) {
        seenCalls.remove(identity)
        callCount -= 1
        if attempt == .repair {
            repairCount -= 1
        }
    }

    private func admissionBudgetExceeded(
        for attempt: FoundationModelToolExecutionAttempt
    ) -> FoundationModelToolBudgetExceeded? {
        if callCount >= budget.maxCalls {
            return .callCount(limit: budget.maxCalls)
        }
        if attempt == .repair, repairCount >= budget.maxRepairs {
            return .repairCount(limit: budget.maxRepairs)
        }
        return durationBudgetExceeded()
    }

    private func durationBudgetExceeded() -> FoundationModelToolBudgetExceeded? {
        guard let limit = budget.maxDuration, elapsedTime() >= limit else {
            return nil
        }
        return .duration(limit: limit)
    }

    private func raceAgainstDuration<Output: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Output
    ) async throws -> FoundationModelTimedToolResult<Output> {
        guard let limit = budget.maxDuration else {
            return .output(try await operation())
        }

        let remaining = limit - elapsedTime()
        guard remaining > .zero else {
            return .deadlineReached
        }

        return try await withThrowingTaskGroup(
            of: FoundationModelTimedToolResult<Output>.self
        ) { group in
            group.addTask {
                .output(try await operation())
            }
            group.addTask {
                try await Task.sleep(for: remaining)
                return .deadlineReached
            }

            let first = try await group.next() ?? .deadlineReached
            group.cancelAll()
            return first
        }
    }

    private static func fingerprint(for identity: CallIdentity) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let bytes = Array(identity.toolName.utf8) + [0] + Array(identity.canonicalArguments)
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
