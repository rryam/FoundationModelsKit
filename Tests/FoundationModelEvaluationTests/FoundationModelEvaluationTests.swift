import Foundation
import Testing
@testable import FoundationModelEvaluation

@Test func traceRoundTripsWithoutPromptOrResponse() throws {
    let fingerprint = FoundationModelRuntimeFingerprint(
        operatingSystem: "iOS", build: "26A", device: "iPhone", modelVariant: "default", contextSize: 4096)
    let trace = FoundationModelExecutionTrace(
        fingerprint: fingerprint, toolCallSequence: ["weather", "calendar"], repairCount: 1,
        latencyMilliseconds: 42, inputTokens: 3, outputTokens: 9, schemaValid: true, succeeded: true)
    let data = try FoundationModelFeedbackBundleBuilder().build(from: trace)
    let decoded = try JSONDecoder().decode(FoundationModelExecutionTrace.self, from: data)
    #expect(decoded == trace)
    #expect(!(String(data: data, encoding: .utf8) ?? "").contains("prompt"))
}

@Test func runnerRecordsFailuresAsErrorCategory() async {
    enum TestError: Error { case refused }
    let runner = FoundationModelEvaluationRunner { _ in throw TestError.refused }
    let result = await runner.run()
    #expect(!result.trace.succeeded)
    #expect(result.trace.errorCategory == "TestError")
}
