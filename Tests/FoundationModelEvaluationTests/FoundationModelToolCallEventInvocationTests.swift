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

        #expect(FoundationModelToolCallEvent(invocation: success).outcome == .succeeded)
        #expect(FoundationModelToolCallEvent(invocation: failure).outcome == .failed)
    }
}
