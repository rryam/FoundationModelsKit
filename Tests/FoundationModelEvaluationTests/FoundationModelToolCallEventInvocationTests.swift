import FoundationModelEvaluation
import FoundationModelsKit
import Testing

@Suite("Routed tool evaluation events")
struct ToolCallEventInvocationTests {
    @Test("Router statuses map to stable evaluation outcomes")
    func mapsRouterStatuses() async throws {
        let router = FoundationModelToolResultRouter<String>()
        let success = try await router.recordSuccess(
            tool: "weather",
            arguments: .object([:]),
            outcome: "sunny"
        )
        let failure = try await router.recordFailure(
            tool: "calendar",
            arguments: .object([:]),
            failure: FoundationModelErrorProjection(category: .networkFailure)
        )
        let authorizationDenial = try await router.record(
            tool: "contacts",
            arguments: .object([:]),
            result: FoundationModelToolExecutionResult<String>.authorizationDenied(
                FoundationModelToolAuthorizationDenial(code: "access_revoked")
            ),
            mapSuccess: { $0 }
        )

        #expect(FoundationModelToolCallEvent(invocation: success).outcome == .succeeded)
        #expect(FoundationModelToolCallEvent(invocation: failure).outcome == .failed)
        #expect(FoundationModelToolCallEvent(invocation: authorizationDenial).outcome == .rejected)
    }
}
