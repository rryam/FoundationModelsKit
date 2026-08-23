import Foundation
import Testing
@testable import FoundationModelsKit

@Suite("Tool execution policy")
struct FoundationModelToolExecutionPolicyTests {
    @Test("Valid calls execute and report actual output tokens")
    func executesValidCall() async throws {
        let policy = FoundationModelToolExecutionPolicy(
            budget: FoundationModelToolExecutionBudget(maxOutputTokens: 10)
        )

        let result = try await policy.execute(
            tool: "weather",
            arguments: .object(["city": .string("Paris")]),
            schema: stringObjectSchema,
            outputTokenEstimator: { $0.count },
            operation: { "sunny" }
        )

        guard case .succeeded(let output, let usage, let outputTokenCount) = result else {
            Issue.record("Expected the tool to execute")
            return
        }
        #expect(output == "sunny")
        #expect(outputTokenCount == 5)
        #expect(usage.callCount == 1)
    }

    @Test("Invalid arguments never execute app code")
    func rejectsInvalidArguments() async throws {
        let probe = ToolOperationProbe()
        let policy = FoundationModelToolExecutionPolicy()

        let result = try await policy.execute(
            tool: "weather",
            arguments: .object([:]),
            schema: stringObjectSchema
        ) {
            await probe.recordExecution()
            return "unreachable"
        }

        guard case .invalidArguments(let issues) = result else {
            Issue.record("Expected invalid arguments")
            return
        }
        #expect(issues.first?.code == .missingRequiredProperty)
        #expect(await probe.executionCount == 0)
    }

    @Test("Canonical argument identity detects repeated calls regardless of object order")
    func detectsRepeatedIdenticalCalls() async throws {
        let policy = FoundationModelToolExecutionPolicy()
        let schema = FoundationModelToolSchema(type: .object, additionalProperties: true)
        let firstArguments = FoundationModelToolValue.object([
            "a": .number(1),
            "b": .number(2)
        ])
        let reorderedArguments = FoundationModelToolValue.object([
            "b": .number(2),
            "a": .number(1)
        ])

        _ = try await policy.execute(
            tool: "read",
            arguments: firstArguments,
            schema: schema,
            operation: { 1 }
        )
        let repeated = try await policy.execute(
            tool: "read",
            arguments: reorderedArguments,
            schema: schema,
            operation: { 2 }
        )

        guard case .loopDetected(let loop) = repeated else {
            Issue.record("Expected loop detection")
            return
        }
        #expect(loop.toolName == "read")
        #expect(!loop.callFingerprint.isEmpty)
    }

    @Test("Call and repair limits are enforced independently")
    func enforcesCallAndRepairLimits() async throws {
        let callPolicy = FoundationModelToolExecutionPolicy(
            budget: FoundationModelToolExecutionBudget(maxCalls: 1)
        )
        let schema = FoundationModelToolSchema(type: .object)

        _ = try await callPolicy.execute(
            tool: "first",
            arguments: .object([:]),
            schema: schema,
            operation: { 1 }
        )
        let callLimited = try await callPolicy.execute(
            tool: "second",
            arguments: .object([:]),
            schema: schema,
            operation: { 2 }
        )
        #expect(callLimited == .budgetExceeded(.callCount(limit: 1)))

        let repairPolicy = FoundationModelToolExecutionPolicy(
            budget: FoundationModelToolExecutionBudget(maxRepairs: 0)
        )
        let repairLimited = try await repairPolicy.execute(
            tool: "repair",
            arguments: .object([:]),
            schema: schema,
            attempt: .repair,
            operation: { 1 }
        )
        #expect(repairLimited == .budgetExceeded(.repairCount(limit: 0)))
    }

    @Test("Duration and actual output-token limits are enforced")
    func enforcesDurationAndOutputLimits() async throws {
        let durationPolicy = FoundationModelToolExecutionPolicy(
            budget: FoundationModelToolExecutionBudget(maxDuration: .seconds(1)),
            elapsedTime: { .seconds(2) }
        )
        let schema = FoundationModelToolSchema(type: .object)

        let durationLimited = try await durationPolicy.execute(
            tool: "slow",
            arguments: .object([:]),
            schema: schema,
            operation: { "output" }
        )
        #expect(durationLimited == .budgetExceeded(.duration(limit: .seconds(1))))

        let outputPolicy = FoundationModelToolExecutionPolicy(
            budget: FoundationModelToolExecutionBudget(maxOutputTokens: 2)
        )
        let outputLimited = try await outputPolicy.execute(
            tool: "large-output",
            arguments: .object([:]),
            schema: schema,
            outputTokenEstimator: { _ in 3 },
            operation: { "output" }
        )
        #expect(outputLimited == .budgetExceeded(.outputTokens(limit: 2, actual: 3)))
    }

    @Test("Duration limit cancels a cooperative long-running tool")
    func cancelsLongRunningTool() async throws {
        let policy = FoundationModelToolExecutionPolicy(
            budget: FoundationModelToolExecutionBudget(maxDuration: .milliseconds(20))
        )
        let result = try await policy.execute(
            tool: "slow",
            arguments: .object([:]),
            schema: FoundationModelToolSchema(type: .object)
        ) {
            try await Task.sleep(for: .seconds(5))
            return "late"
        }

        #expect(result == .budgetExceeded(.duration(limit: .milliseconds(20))))
    }

    @Test("Side effects require confirmation or a valid idempotency key")
    func protectsSideEffects() async throws {
        let schema = FoundationModelToolSchema(type: .object)
        let confirmationPolicy = FoundationModelToolExecutionPolicy()
        let confirmationResult = try await confirmationPolicy.execute(
            tool: "delete",
            arguments: .object([:]),
            schema: schema,
            effect: .sideEffect(.confirmation),
            operation: { true }
        )
        guard case .confirmationRequired(let request) = confirmationResult else {
            Issue.record("Expected confirmation to be required")
            return
        }
        #expect(request.toolName == "delete")

        let idempotencyPolicy = FoundationModelToolExecutionPolicy()
        let invalidKeyResult = try await idempotencyPolicy.execute(
            tool: "create",
            arguments: .object([:]),
            schema: schema,
            effect: .sideEffect(.idempotency(key: "  ")),
            operation: { true }
        )
        guard case .invalidArguments(let issues) = invalidKeyResult else {
            Issue.record("Expected the empty idempotency key to be rejected")
            return
        }
        #expect(issues.first?.code == .invalidIdempotencyKey)
    }

    @Test("Approved confirmation executes the side effect once")
    func approvedConfirmationExecutes() async throws {
        let confirmer = ApprovingConfirmer()
        let policy = FoundationModelToolExecutionPolicy()
        let result = try await policy.execute(
            tool: "save",
            arguments: .object([:]),
            schema: FoundationModelToolSchema(type: .object),
            effect: .sideEffect(.confirmation),
            confirmer: confirmer,
            operation: { "saved" }
        )

        guard case .succeeded(let output, _, _) = result else {
            Issue.record("Expected confirmed side effect to execute")
            return
        }
        #expect(output == "saved")
        #expect(await confirmer.confirmationCount == 1)
    }

    @Test("An idempotency key cannot be reused with different arguments")
    func rejectsIdempotencyKeyConflict() async throws {
        let policy = FoundationModelToolExecutionPolicy()
        let schema = FoundationModelToolSchema(type: .object, additionalProperties: true)

        _ = try await policy.execute(
            tool: "create",
            arguments: .object(["value": .string("first")]),
            schema: schema,
            effect: .sideEffect(.idempotency(key: "request-1")),
            operation: { true }
        )
        let conflict = try await policy.execute(
            tool: "create",
            arguments: .object(["value": .string("second")]),
            schema: schema,
            effect: .sideEffect(.idempotency(key: "request-1")),
            operation: { true }
        )

        guard case .invalidArguments(let issues) = conflict else {
            Issue.record("Expected an idempotency key conflict")
            return
        }
        #expect(issues.first?.code == .idempotencyKeyConflict)
    }

    private var stringObjectSchema: FoundationModelToolSchema {
        FoundationModelToolSchema(
            type: .object,
            properties: ["city": FoundationModelToolSchema(type: .string)],
            required: ["city"]
        )
    }
}

private actor ToolOperationProbe {
    private(set) var executionCount = 0

    func recordExecution() {
        executionCount += 1
    }
}

private actor ApprovingConfirmer: FoundationModelToolExecutionConfirming {
    private(set) var confirmationCount = 0

    func confirm(
        _ request: FoundationModelToolConfirmationRequest,
        arguments: FoundationModelToolValue
    ) -> Bool {
        confirmationCount += 1
        return true
    }
}
