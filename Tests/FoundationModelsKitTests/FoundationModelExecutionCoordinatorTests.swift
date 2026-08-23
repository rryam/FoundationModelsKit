import Foundation
import Testing
@testable import FoundationModelsKit

@Suite("Foundation Model Execution Coordinator")
struct FoundationModelExecutionCoordinatorTests {
    @Test("Transient request failures open the circuit and use an explicit fallback")
    func transientFailureUsesFallback() async throws {
        let primaryProbe = InvocationProbe()
        let fallbackProbe = InvocationProbe()
        let store = FoundationModelInMemoryCircuitStateStore()
        let resetDate = Date(timeIntervalSince1970: 2_000)
        let coordinator = try FoundationModelExecutionCoordinator<String, String>(
            primary: FoundationModelExecutionRoute(runtime: .privateCloudCompute) { request in
                await primaryProbe.record(request)
                throw StubExecutionError(category: .rateLimited, resetDate: resetDate)
            },
            fallbacks: [
                FoundationModelExecutionRoute(
                    runtime: .onDevice,
                    prepareForFallback: { request, transition in
                        #expect(transition.sourceRuntime == .privateCloudCompute)
                        #expect(transition.destinationRuntime == .onDevice)
                        #expect(transition.trigger?.category == .rateLimited)
                        return "reconciled:\(request)"
                    },
                    execute: { request in
                        await fallbackProbe.record(request)
                        return "fallback:\(request)"
                    }
                )
            ],
            circuitStateStore: store,
            errorProjector: projectStubError,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let result = try await coordinator.execute(
            "request",
            safety: .readOnlyOrIdempotent,
            correlationID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )

        #expect(result.output == "fallback:reconciled:request")
        #expect(result.trace.selectedRuntime == .onDevice)
        #expect(result.trace.attempts.count == 2)
        #expect(result.trace.attempts[0].outcome == .failed)
        #expect(result.trace.attempts[0].failure?.category == .rateLimited)
        #expect(result.trace.attempts[0].nextProbeAt == resetDate)
        #expect(result.trace.attempts[0].cooldown == 1_000)
        #expect(result.trace.attempts[0].retryDecision == .useFallback(.onDevice))
        #expect(result.trace.attempts[1].outcome == .succeeded)
        #expect(await primaryProbe.values() == ["request"])
        #expect(await fallbackProbe.values() == ["reconciled:request"])

        let circuit = try #require(await store.circuitState(for: .privateCloudCompute))
        #expect(circuit.phase == .open)
        #expect(circuit.failureCategory == .rateLimited)
        #expect(circuit.nextProbeAt == resetDate)
    }

    @Test("An open primary circuit is skipped without re-executing it")
    func openCircuitSkipsPrimary() async throws {
        let primaryProbe = InvocationProbe()
        let fallbackProbe = InvocationProbe()
        let store = FoundationModelInMemoryCircuitStateStore()
        let coordinator = try FoundationModelExecutionCoordinator<String, String>(
            primary: FoundationModelExecutionRoute(runtime: .privateCloudCompute) { request in
                await primaryProbe.record(request)
                throw StubExecutionError(category: .serviceUnavailable)
            },
            fallbacks: [
                FoundationModelExecutionRoute(runtime: .onDevice) { request in
                    await fallbackProbe.record(request)
                    return request
                }
            ],
            policy: FoundationModelExecutionPolicy(defaultCooldown: 600),
            circuitStateStore: store,
            errorProjector: projectStubError,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        _ = try await coordinator.execute("first", safety: .readOnlyOrIdempotent)
        let second = try await coordinator.execute("second", safety: .readOnlyOrIdempotent)

        #expect(await primaryProbe.values() == ["first"])
        #expect(await fallbackProbe.values() == ["first", "second"])
        #expect(second.trace.attempts[0].outcome == .skippedOpenCircuit)
        #expect(second.trace.attempts[0].retryDecision == .useFallback(.onDevice))
        #expect(second.trace.attempts[1].outcome == .succeeded)
    }

    @Test("A successful half-open probe closes its persisted circuit")
    func successfulHalfOpenProbeClosesCircuit() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let store = FoundationModelInMemoryCircuitStateStore(
            states: [
                .privateCloudCompute: FoundationModelCircuitState(
                    phase: .open,
                    failureCategory: .networkFailure,
                    openedAt: date.addingTimeInterval(-600),
                    nextProbeAt: date.addingTimeInterval(-1),
                    consecutiveFailures: 2
                )
            ]
        )
        let coordinator = try FoundationModelExecutionCoordinator<String, String>(
            primary: FoundationModelExecutionRoute(runtime: .privateCloudCompute) { request in request },
            circuitStateStore: store,
            now: { date }
        )

        let result = try await coordinator.execute("probe", safety: .readOnlyOrIdempotent)

        #expect(result.output == "probe")
        #expect(result.trace.attempts.first?.circuitPhase == .halfOpen)
        #expect(await store.circuitState(for: .privateCloudCompute) == nil)
    }

    @Test("Non-retryable model failures do not reach a fallback")
    func nonRetryableFailureStopsRouting() async throws {
        let fallbackProbe = InvocationProbe()
        let store = FoundationModelInMemoryCircuitStateStore()
        let coordinator = try FoundationModelExecutionCoordinator<String, String>(
            primary: FoundationModelExecutionRoute(runtime: .privateCloudCompute) { _ in
                throw StubExecutionError(category: .guardrailViolation)
            },
            fallbacks: [
                FoundationModelExecutionRoute(runtime: .onDevice) { request in
                    await fallbackProbe.record(request)
                    return request
                }
            ],
            circuitStateStore: store,
            errorProjector: projectStubError
        )

        do {
            _ = try await coordinator.execute("request", safety: .readOnlyOrIdempotent)
            Issue.record("Expected routing to stop at the guardrail failure")
        } catch let failure as FoundationModelExecutionFailure {
            #expect(failure.trace.attempts.count == 1)
            #expect(failure.trace.attempts[0].failure?.category == .guardrailViolation)
            #expect(failure.trace.attempts[0].retryDecision == .stop(.failureNotRetryable))
        }

        #expect(await fallbackProbe.values().isEmpty)
        #expect(await store.circuitState(for: .privateCloudCompute) == nil)
    }

    @Test("Potentially side-effecting requests never retry after an attempted execution")
    func sideEffectingFailureStopsRouting() async throws {
        let fallbackProbe = InvocationProbe()
        let store = FoundationModelInMemoryCircuitStateStore()
        let coordinator = try FoundationModelExecutionCoordinator<String, String>(
            primary: FoundationModelExecutionRoute(runtime: .privateCloudCompute) { _ in
                throw StubExecutionError(category: .networkFailure)
            },
            fallbacks: [
                FoundationModelExecutionRoute(runtime: .onDevice) { request in
                    await fallbackProbe.record(request)
                    return request
                }
            ],
            circuitStateStore: store,
            errorProjector: projectStubError
        )

        do {
            _ = try await coordinator.execute("mutate", safety: .mayHaveSideEffects)
            Issue.record("Expected side-effecting routing to stop after the first attempt")
        } catch let failure as FoundationModelExecutionFailure {
            #expect(failure.trace.attempts.count == 1)
            #expect(failure.trace.attempts[0].retryDecision == .stop(.mayHaveSideEffects))
        }

        #expect(await fallbackProbe.values().isEmpty)
        #expect(await store.circuitState(for: .privateCloudCompute)?.failureCategory == .networkFailure)
    }

    @Test("Concurrent callers share one serialized execution lane")
    func concurrentCallersAreSerialized() async throws {
        let concurrencyProbe = ConcurrencyProbe()
        let coordinator = try FoundationModelExecutionCoordinator<Int, Int>(
            primary: FoundationModelExecutionRoute(runtime: .onDevice) { request in
                await concurrencyProbe.begin()
                try await Task.sleep(for: .milliseconds(20))
                await concurrencyProbe.end()
                return request
            },
            circuitStateStore: FoundationModelInMemoryCircuitStateStore()
        )

        async let first = coordinator.execute(1, safety: .readOnlyOrIdempotent)
        async let second = coordinator.execute(2, safety: .readOnlyOrIdempotent)
        async let third = coordinator.execute(3, safety: .readOnlyOrIdempotent)
        let outputs = try await [first.output, second.output, third.output]

        #expect(Set(outputs) == [1, 2, 3])
        #expect(await concurrencyProbe.maximumConcurrentExecutions() == 1)
    }

    @Test("Separate coordinators serialize through one shared execution gate")
    func separateCoordinatorsAreSerialized() async throws {
        let concurrencyProbe = ConcurrencyProbe()
        let gate = FoundationModelExecutionGate()
        let store = FoundationModelInMemoryCircuitStateStore()
        let firstCoordinator = try FoundationModelExecutionCoordinator<Int, Int>(
            primary: FoundationModelExecutionRoute(runtime: .onDevice) { request in
                await concurrencyProbe.begin()
                try await Task.sleep(for: .milliseconds(20))
                await concurrencyProbe.end()
                return request
            },
            circuitStateStore: store,
            executionGate: gate
        )
        let secondCoordinator = try FoundationModelExecutionCoordinator<Int, Int>(
            primary: FoundationModelExecutionRoute(runtime: .onDevice) { request in
                await concurrencyProbe.begin()
                try await Task.sleep(for: .milliseconds(20))
                await concurrencyProbe.end()
                return request
            },
            circuitStateStore: store,
            executionGate: gate
        )

        async let first = firstCoordinator.execute(1, safety: .readOnlyOrIdempotent)
        async let second = secondCoordinator.execute(2, safety: .readOnlyOrIdempotent)
        let outputs = try await [first.output, second.output]

        #expect(Set(outputs) == [1, 2])
        #expect(await concurrencyProbe.maximumConcurrentExecutions() == 1)
    }

    @Test("Circuit admission reserves only one half-open probe")
    func halfOpenAdmissionIsAtomic() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let store = FoundationModelInMemoryCircuitStateStore(states: [
            .privateCloudCompute: FoundationModelCircuitState(
                phase: .open,
                failureCategory: .rateLimited,
                openedAt: date.addingTimeInterval(-100),
                nextProbeAt: date.addingTimeInterval(-1),
                consecutiveFailures: 1
            )
        ])

        async let first = store.admission(
            for: .privateCloudCompute,
            at: date,
            halfOpenProbeInterval: 300
        )
        async let second = store.admission(
            for: .privateCloudCompute,
            at: date,
            halfOpenProbeInterval: 300
        )
        let admissions = await [first, second]

        let permittedCount = admissions.filter {
            if case .permitted(phase: .halfOpen, previousState: _) = $0 {
                return true
            }
            return false
        }.count
        let rejectedCount = admissions.filter {
            if case .rejected = $0 {
                return true
            }
            return false
        }.count
        #expect(permittedCount == 1)
        #expect(rejectedCount == 1)
    }

    @Test("Durable circuit store round-trips and clears state")
    func userDefaultsStoreRoundTripsCircuitState() async throws {
        let suiteName = "FoundationModelExecutionCoordinatorTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = try #require(FoundationModelDefaultsCircuitStore(
            suiteName: suiteName,
            keyPrefix: "routing"
        ))
        let state = FoundationModelCircuitState(
            phase: .open,
            failureCategory: .quotaLimitReached,
            openedAt: Date(timeIntervalSince1970: 1_000),
            nextProbeAt: Date(timeIntervalSince1970: 2_000),
            consecutiveFailures: 3
        )

        await store.setCircuitState(state, for: .privateCloudCompute)

        #expect(await store.circuitState(for: .privateCloudCompute) == state)

        await store.setCircuitState(nil, for: .privateCloudCompute)

        #expect(await store.circuitState(for: .privateCloudCompute) == nil)
    }

    @Test("Duplicate runtimes are rejected")
    func duplicateRuntimesAreRejected() {
        #expect(throws: FoundationModelsKitError.self) {
            _ = try FoundationModelExecutionCoordinator<String, String>(
                primary: FoundationModelExecutionRoute(runtime: .onDevice) { request in request },
                fallbacks: [
                    FoundationModelExecutionRoute(runtime: .onDevice) { request in request }
                ]
            )
        }
    }
}

private struct StubExecutionError: Error, Sendable {
    let category: FoundationModelErrorProjection.Category
    let resetDate: Date?

    init(
        category: FoundationModelErrorProjection.Category,
        resetDate: Date? = nil
    ) {
        self.category = category
        self.resetDate = resetDate
    }
}

private let projectStubError: FoundationModelExecutionCoordinator<String, String>.ErrorProjector = { error in
    guard let error = error as? StubExecutionError else { return nil }
    return FoundationModelErrorProjection(
        category: error.category,
        resetDate: error.resetDate
    )
}

private actor InvocationProbe {
    private var recordedValues: [String] = []

    func record(_ value: String) {
        recordedValues.append(value)
    }

    func values() -> [String] {
        recordedValues
    }
}

private actor ConcurrencyProbe {
    private var activeExecutions = 0
    private var maximumExecutions = 0

    func begin() {
        activeExecutions += 1
        maximumExecutions = max(maximumExecutions, activeExecutions)
    }

    func end() {
        activeExecutions -= 1
    }

    func maximumConcurrentExecutions() -> Int {
        maximumExecutions
    }
}
