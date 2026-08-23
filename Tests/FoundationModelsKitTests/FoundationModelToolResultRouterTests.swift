import Foundation
import Testing
@testable import FoundationModelsKit

@Suite("Tool result router")
struct FoundationModelToolResultRouterTests {
    private enum AppOutcome: Codable, Equatable, Sendable {
        case sleep(hours: Double)
        case exercise(minutes: Int)
    }

    @Test("No successful tools produces no routed outcome")
    func noSuccessfulTools() async {
        let router = FoundationModelToolResultRouter<AppOutcome>()

        #expect(await router.routingResult() == .none)
        #expect(await router.snapshot().isEmpty)
    }

    @Test("Different tool result types route through one app enum")
    func routesTypedOutcomesInOrder() async throws {
        let router = FoundationModelToolResultRouter<AppOutcome>()
        let first = try await router.recordSuccess(
            tool: "sleep",
            arguments: .object(["month": .string("November")]),
            outcome: .sleep(hours: 7.5),
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            recordedAt: Date(timeIntervalSince1970: 1_000)
        )
        let second = try await router.recordSuccess(
            tool: "exercise",
            arguments: .object(["days": .number(7)]),
            outcome: .exercise(minutes: 90),
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            recordedAt: Date(timeIntervalSince1970: 1_001)
        )

        #expect(first.sequence == 0)
        #expect(second.sequence == 1)
        #expect(
            await router.routingResult() == .many([
                .sleep(hours: 7.5),
                .exercise(minutes: 90)
            ])
        )
    }

    @Test("Raw arguments are omitted by default and can be explicitly retained")
    func controlsArgumentRecording() async throws {
        let arguments = FoundationModelToolValue.object([
            "a": .number(1),
            "b": .number(2)
        ])
        let reordered = FoundationModelToolValue.object([
            "b": .number(2),
            "a": .number(1)
        ])
        let defaultRouter = FoundationModelToolResultRouter<AppOutcome>()
        let retainingRouter = FoundationModelToolResultRouter<AppOutcome>(
            argumentRecording: .includeArguments
        )

        let omitted = try await defaultRouter.recordSuccess(
            tool: "sleep",
            arguments: arguments,
            outcome: .sleep(hours: 8)
        )
        let retained = try await retainingRouter.recordSuccess(
            tool: "sleep",
            arguments: reordered,
            outcome: .sleep(hours: 8)
        )

        #expect(omitted.arguments == nil)
        #expect(retained.arguments == reordered)
        #expect(omitted.argumentFingerprint == retained.argumentFingerprint)
    }

    @Test("Policy decisions record rejections without routing an outcome")
    func recordsPolicyDecision() async throws {
        let router = FoundationModelToolResultRouter<AppOutcome>()
        let policyResult = FoundationModelToolExecutionResult<Int>.invalidArguments([])

        let invocation = try await router.record(
            tool: "sleep",
            arguments: .object([:]),
            result: policyResult,
            mapSuccess: { .exercise(minutes: $0) }
        )

        #expect(invocation.status == .invalidArguments)
        #expect(invocation.outcome == nil)
        #expect(await router.routingResult() == .none)
    }

    @Test("Projected failures remain typed and Codable")
    func recordsAndRoundTripsFailure() async throws {
        let router = FoundationModelToolResultRouter<AppOutcome>()
        let invocation = try await router.recordFailure(
            tool: "sleep",
            arguments: .object([:]),
            failure: FoundationModelErrorProjection(category: .networkFailure),
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            recordedAt: Date(timeIntervalSince1970: 1_002)
        )

        let data = try JSONEncoder().encode(invocation)
        let decoded = try JSONDecoder().decode(
            FoundationModelToolInvocation<AppOutcome>.self,
            from: data
        )

        #expect(decoded == invocation)
        #expect(decoded.failure?.category == .networkFailure)
    }
}
