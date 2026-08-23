import Foundation

/// Serializes Foundation Models work and routes transient failures through explicit app-supplied fallbacks.
public actor FoundationModelExecutionCoordinator<Request: Sendable, Output: Sendable> {
    public typealias Route = FoundationModelExecutionRoute<Request, Output>
    public typealias ErrorProjector = @Sendable (any Error) -> FoundationModelErrorProjection?

    private struct WaitingExecution {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let routes: [Route]
    private let policy: FoundationModelExecutionPolicy
    private let circuitStateStore: any FoundationModelCircuitStatePersisting
    private let errorProjector: ErrorProjector
    private let now: @Sendable () -> Date

    private var isExecuting = false
    private var waitingExecutions: [WaitingExecution] = []

    public init(
        primary: Route,
        fallbacks: [Route] = [],
        policy: FoundationModelExecutionPolicy = .default,
        circuitStateStore: any FoundationModelCircuitStatePersisting = FoundationModelInMemoryCircuitStateStore(),
        errorProjector: @escaping ErrorProjector = FoundationModelErrorProjection.project,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        let routes = [primary] + fallbacks
        guard Set(routes.map(\.runtime)).count == routes.count else {
            throw FoundationModelsKitError.invalidRequest(
                "Execution coordinator routes must use unique runtimes."
            )
        }
        guard policy.defaultCooldown >= 0, policy.halfOpenProbeInterval >= 0 else {
            throw FoundationModelsKitError.invalidRequest(
                "Execution coordinator cooldowns must not be negative."
            )
        }

        self.routes = routes
        self.policy = policy
        self.circuitStateStore = circuitStateStore
        self.errorProjector = errorProjector
        self.now = now
    }

    /// Executes a request on one serialized lane shared by every caller of this coordinator.
    ///
    /// Automatic fallback after an attempted execution is permitted only for transient runtime
    /// failures and requests declared `readOnlyOrIdempotent`.
    public func execute(
        _ request: Request,
        safety: FoundationModelExecutionSafety,
        correlationID: UUID = UUID()
    ) async throws -> FoundationModelRoutedResult<Output> {
        let executionID = UUID()
        try await acquireExecutionSlot(id: executionID)

        do {
            let result = try await executeSerially(
                request,
                safety: safety,
                correlationID: correlationID
            )
            releaseExecutionSlot()
            return result
        } catch {
            releaseExecutionSlot()
            throw error
        }
    }

    private func executeSerially(
        _ request: Request,
        safety: FoundationModelExecutionSafety,
        correlationID: UUID
    ) async throws -> FoundationModelRoutedResult<Output> {
        let traceStartedAt = now()
        var attempts: [FoundationModelRoutingTrace.Attempt] = []
        var previousRuntime: FoundationModelRuntime?
        var transitionTrigger: FoundationModelErrorProjection?
        var lastError: (any Error)?

        for index in routes.indices {
            try Task.checkCancellation()

            let route = routes[index]
            let attemptStartedAt = now()
            let storedState = await circuitStateStore.circuitState(for: route.runtime)
            let circuitPhase = await prepareCircuitForAttempt(
                storedState,
                runtime: route.runtime,
                at: attemptStartedAt
            )

            if let storedState, circuitPhase == .open {
                let retryDecision = retryDecisionForSkippedRoute(after: index)
                attempts.append(
                    FoundationModelRoutingTrace.Attempt(
                        runtime: route.runtime,
                        startedAt: attemptStartedAt,
                        finishedAt: now(),
                        circuitPhase: .open,
                        outcome: .skippedOpenCircuit,
                        failure: FoundationModelErrorProjection(
                            category: storedState.failureCategory
                        ),
                        nextProbeAt: storedState.nextProbeAt,
                        retryDecision: retryDecision
                    )
                )

                guard index + 1 < routes.count else {
                    throw terminalFailure(
                        correlationID: correlationID,
                        startedAt: traceStartedAt,
                        attempts: attempts,
                        underlyingError: lastError
                    )
                }

                previousRuntime = route.runtime
                transitionTrigger = FoundationModelErrorProjection(
                    category: storedState.failureCategory
                )
                continue
            }

            var preparedRequest = request
            if let previousRuntime {
                let transition = FoundationModelRouteTransition(
                    sourceRuntime: previousRuntime,
                    destinationRuntime: route.runtime,
                    trigger: transitionTrigger
                )

                do {
                    preparedRequest = try await route.prepare(request, for: transition)
                } catch {
                    let failure = errorProjector(error)
                    attempts.append(
                        FoundationModelRoutingTrace.Attempt(
                            runtime: route.runtime,
                            startedAt: attemptStartedAt,
                            finishedAt: now(),
                            circuitPhase: circuitPhase,
                            outcome: .preparationFailed,
                            failure: failure,
                            errorType: String(reflecting: type(of: error)),
                            retryDecision: .stop(.preparationFailed)
                        )
                    )
                    throw terminalFailure(
                        correlationID: correlationID,
                        startedAt: traceStartedAt,
                        attempts: attempts,
                        underlyingError: error
                    )
                }
            }

            do {
                let output = try await route.execute(preparedRequest)
                try Task.checkCancellation()
                await circuitStateStore.setCircuitState(nil, for: route.runtime)
                let finishedAt = now()
                attempts.append(
                    FoundationModelRoutingTrace.Attempt(
                        runtime: route.runtime,
                        startedAt: attemptStartedAt,
                        finishedAt: finishedAt,
                        circuitPhase: circuitPhase,
                        outcome: .succeeded,
                        retryDecision: .notNeeded
                    )
                )

                return FoundationModelRoutedResult(
                    output: output,
                    trace: FoundationModelRoutingTrace(
                        correlationID: correlationID,
                        startedAt: traceStartedAt,
                        finishedAt: finishedAt,
                        attempts: attempts,
                        selectedRuntime: route.runtime
                    )
                )
            } catch is CancellationError {
                await circuitStateStore.setCircuitState(storedState, for: route.runtime)
                throw CancellationError()
            } catch {
                let failure = errorProjector(error)
                let nextProbeAt = await updateCircuit(
                    after: failure,
                    previousState: storedState,
                    attemptedPhase: circuitPhase,
                    runtime: route.runtime
                )
                let retryDecision = retryDecision(
                    after: failure,
                    safety: safety,
                    routeIndex: index
                )
                attempts.append(
                    FoundationModelRoutingTrace.Attempt(
                        runtime: route.runtime,
                        startedAt: attemptStartedAt,
                        finishedAt: now(),
                        circuitPhase: circuitPhase,
                        outcome: .failed,
                        failure: failure,
                        errorType: String(reflecting: type(of: error)),
                        nextProbeAt: nextProbeAt,
                        retryDecision: retryDecision
                    )
                )

                guard case .useFallback = retryDecision else {
                    throw terminalFailure(
                        correlationID: correlationID,
                        startedAt: traceStartedAt,
                        attempts: attempts,
                        underlyingError: error
                    )
                }

                previousRuntime = route.runtime
                transitionTrigger = failure
                lastError = error
            }
        }

        throw terminalFailure(
            correlationID: correlationID,
            startedAt: traceStartedAt,
            attempts: attempts,
            underlyingError: lastError
        )
    }

    private func prepareCircuitForAttempt(
        _ state: FoundationModelCircuitState?,
        runtime: FoundationModelRuntime,
        at date: Date
    ) async -> FoundationModelCircuitState.Phase? {
        guard let state else { return nil }
        guard state.nextProbeAt <= date else { return .open }

        let halfOpenState = FoundationModelCircuitState(
            phase: .halfOpen,
            failureCategory: state.failureCategory,
            openedAt: state.openedAt,
            nextProbeAt: date.addingTimeInterval(policy.halfOpenProbeInterval),
            consecutiveFailures: state.consecutiveFailures
        )
        await circuitStateStore.setCircuitState(halfOpenState, for: runtime)
        return .halfOpen
    }

    private func updateCircuit(
        after failure: FoundationModelErrorProjection?,
        previousState: FoundationModelCircuitState?,
        attemptedPhase: FoundationModelCircuitState.Phase?,
        runtime: FoundationModelRuntime
    ) async -> Date? {
        guard let failure,
              FoundationModelExecutionPolicy.circuitBreakingCategories.contains(failure.category) else {
            await circuitStateStore.setCircuitState(nil, for: runtime)
            return nil
        }

        let date = now()
        let fallbackInterval = attemptedPhase == .halfOpen
            ? policy.halfOpenProbeInterval
            : policy.defaultCooldown
        let nextProbeAt = failure.resetDate.map { max($0, date) }
            ?? date.addingTimeInterval(fallbackInterval)
        let state = FoundationModelCircuitState(
            phase: .open,
            failureCategory: failure.category,
            openedAt: previousState?.openedAt ?? date,
            nextProbeAt: nextProbeAt,
            consecutiveFailures: (previousState?.consecutiveFailures ?? 0) + 1
        )
        await circuitStateStore.setCircuitState(state, for: runtime)
        return nextProbeAt
    }

    private func retryDecision(
        after failure: FoundationModelErrorProjection?,
        safety: FoundationModelExecutionSafety,
        routeIndex: Int
    ) -> FoundationModelRoutingTrace.RetryDecision {
        guard let failure,
              FoundationModelExecutionPolicy.circuitBreakingCategories.contains(failure.category) else {
            return .stop(.failureNotRetryable)
        }
        guard safety == .readOnlyOrIdempotent else {
            return .stop(.mayHaveSideEffects)
        }
        guard routeIndex + 1 < routes.count else {
            return .stop(.noFallback)
        }
        return .useFallback(routes[routeIndex + 1].runtime)
    }

    private func retryDecisionForSkippedRoute(
        after routeIndex: Int
    ) -> FoundationModelRoutingTrace.RetryDecision {
        guard routeIndex + 1 < routes.count else {
            return .stop(.circuitOpen)
        }
        return .useFallback(routes[routeIndex + 1].runtime)
    }

    private func terminalFailure(
        correlationID: UUID,
        startedAt: Date,
        attempts: [FoundationModelRoutingTrace.Attempt],
        underlyingError: (any Error)?
    ) -> FoundationModelExecutionFailure {
        FoundationModelExecutionFailure(
            trace: FoundationModelRoutingTrace(
                correlationID: correlationID,
                startedAt: startedAt,
                finishedAt: now(),
                attempts: attempts,
                selectedRuntime: nil
            ),
            underlyingError: underlyingError
        )
    }

    private func acquireExecutionSlot(id: UUID) async throws {
        try Task.checkCancellation()

        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isExecuting {
                    waitingExecutions.append(
                        WaitingExecution(id: id, continuation: continuation)
                    )
                } else {
                    isExecuting = true
                    continuation.resume(returning: true)
                }
            }
        } onCancel: {
            Task { await self.cancelWaitingExecution(id: id) }
        }

        guard acquired else { throw CancellationError() }
        if Task.isCancelled {
            releaseExecutionSlot()
            throw CancellationError()
        }
    }

    private func cancelWaitingExecution(id: UUID) {
        guard let index = waitingExecutions.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waitingExecution = waitingExecutions.remove(at: index)
        waitingExecution.continuation.resume(returning: false)
    }

    private func releaseExecutionSlot() {
        guard !waitingExecutions.isEmpty else {
            isExecuting = false
            return
        }
        let nextExecution = waitingExecutions.removeFirst()
        nextExecution.continuation.resume(returning: true)
    }
}
