import Foundation
import Testing
import FoundationModelsKit
@testable import FoundationModelEvaluation

@Test func runnerRecordsTimingAndTypedMetadata() async {
    let scenario = FoundationModelEvaluationScenario(
        toolCalls: [FoundationModelToolCallEvent(name: "weather", sequence: 0)], repairCount: 2,
        tokenUsage: ModelTokenUsage(inputTokenCount: 4, measurement: .estimated), schemaValid: true)
    let trace = await FoundationModelEvaluationRunner { _ in }.run(scenario: scenario)
    #expect(trace.outcome == .succeeded)
    #expect(trace.durationNanoseconds >= 0)
    #expect(trace.toolCalls == scenario.toolCalls)
    #expect(trace.tokenUsage == scenario.tokenUsage)
}

@Test func runnerProjectsFailure() async {
    struct TestFailure: Error {}
    let trace = await FoundationModelEvaluationRunner { _ in throw TestFailure() }.run()
    #expect(trace.durationNanoseconds >= 0)
    if case .failed(let projection) = trace.outcome { #expect(projection == nil) }
    else { Issue.record("Expected failed outcome") }
}

@Test func fingerprintAndBundleEncodeMetadataOnly() throws {
    let fingerprint = FoundationModelRuntimeFingerprint(operatingSystem: "26.0", operatingSystemBuild: "A1", deviceModelIdentifier: "iPhone", locale: "en_US")
    let trace = FoundationModelExecutionTrace(fingerprint: fingerprint, durationNanoseconds: 12, outcome: .succeeded)
    let data = try FoundationModelFeedbackBundleBuilder().build(trace: trace, appleLanguageModelFeedbackAttachment: Data([1, 2]))
    let bundle = try JSONDecoder().decode(FoundationModelFeedbackBundle.self, from: data)
    #expect(bundle.trace == trace)
    #expect(bundle.appleLanguageModelFeedbackAttachment == Data([1, 2]))
    #expect(!(String(data: data, encoding: .utf8) ?? "").contains("prompt"))
}
