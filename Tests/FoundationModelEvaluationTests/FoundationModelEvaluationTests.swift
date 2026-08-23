import Foundation
import FoundationModelsKit
import Testing
@testable import FoundationModelEvaluation

@Suite("Foundation Model evaluation evidence")
struct FoundationModelEvaluationTests {
    @Test("Runner records environment, ordered tools, latency, tokens, and final success")
    func runnerRecordsSuccessfulObservation() async {
        let fingerprint = FoundationModelRuntimeFingerprint(
            operatingSystemName: "iOS",
            operatingSystemVersion: "27.0",
            operatingSystemBuild: "24A1",
            deviceModelIdentifier: "iPhone19,1",
            modelVariant: "Core Advanced 3",
            contextSize: 8_192,
            runtime: .onDevice,
            localeIdentifier: "en_US"
        )
        let tokenUsage = ModelTokenUsage(
            input: .init(totalTokenCount: 20),
            output: .init(totalTokenCount: 5),
            measurement: .observed,
            scope: .response
        )
        let runner = FoundationModelEvaluationRunner()

        let trace = await runner.run(fingerprint: fingerprint) {
            FoundationModelEvaluationObservation(
                toolCallSequence: [
                    FoundationModelToolCallEvent(
                        sequence: 1,
                        toolName: "weather",
                        outcome: .succeeded
                    ),
                    FoundationModelToolCallEvent(
                        sequence: 0,
                        toolName: "location",
                        outcome: .succeeded
                    )
                ],
                repairCount: 1,
                timeToFirstToken: 0.1,
                tokenUsage: tokenUsage,
                schemaValid: true,
                finalSuccess: true
            )
        }

        #expect(trace.fingerprint == fingerprint)
        #expect(trace.toolCallSequence.map(\.toolName) == ["location", "weather"])
        #expect(trace.repairCount == 1)
        #expect(trace.latency.total >= 0)
        #expect(trace.latency.timeToFirstToken == 0.1)
        #expect(trace.tokenUsage == tokenUsage)
        #expect(trace.schemaValid == true)
        #expect(trace.outcome == .completed)
        #expect(trace.finalSuccess)
    }

    @Test("Runner classifies refusal categories and failed final status")
    func runnerClassifiesRefusal() async {
        struct RefusalError: Error {}
        let runner = FoundationModelEvaluationRunner { _ in
            FoundationModelErrorProjection(category: .refusal)
        }

        let trace = await runner.run(fingerprint: testFingerprint) {
            throw RefusalError()
        }

        #expect(trace.outcome == .refused)
        #expect(trace.refusalOrErrorCategory == .refusal)
        #expect(!trace.finalSuccess)
    }

    @Test("Schema invalidity makes a completed run unsuccessful")
    func schemaInvalidityFailsFinalEvaluation() async {
        let trace = await FoundationModelEvaluationRunner().run(fingerprint: testFingerprint) {
            FoundationModelEvaluationObservation(schemaValid: false)
        }

        #expect(trace.outcome == .completed)
        #expect(trace.schemaValid == false)
        #expect(!trace.finalSuccess)
    }

    @Test("Cancellation is preserved as a terminal evaluation outcome")
    func runnerRecordsCancellation() async {
        let trace = await FoundationModelEvaluationRunner().run(fingerprint: testFingerprint) {
            throw CancellationError()
        }

        #expect(trace.outcome == .cancelled)
        #expect(trace.refusalOrErrorCategory == nil)
        #expect(!trace.finalSuccess)
    }

    @Test("Feedback builder keeps metadata and Apple diagnostics as separate attachments")
    func builderProducesSeparateAttachments() async throws {
        let trace = await FoundationModelEvaluationRunner().run(fingerprint: testFingerprint) {
            FoundationModelEvaluationObservation()
        }
        let builder = FoundationModelFeedbackBundleBuilder()
        let appleData = Data([1, 2, 3])
        let bundle = builder.build(
            trace: trace,
            appleLanguageModelFeedbackAttachment: appleData
        )

        let attachments = try builder.attachments(for: bundle)

        #expect(attachments.map(\.suggestedFileName) == [
            "foundation-model-evaluation.json",
            "language-model-feedback.data"
        ])
        #expect(attachments[1].data == appleData)
        let metadataText = try #require(String(data: attachments[0].data, encoding: .utf8))
        #expect(!metadataText.contains("prompt"))
        #expect(!metadataText.contains(appleData.base64EncodedString()))
    }

    @Test("Fingerprints round-trip all public runtime fields")
    func fingerprintRoundTrips() throws {
        let data = try JSONEncoder().encode(testFingerprint)
        let decoded = try JSONDecoder().decode(
            FoundationModelRuntimeFingerprint.self,
            from: data
        )

        #expect(decoded == testFingerprint)
    }

    private var testFingerprint: FoundationModelRuntimeFingerprint {
        FoundationModelRuntimeFingerprint(
            operatingSystemName: "macOS",
            operatingSystemVersion: "26.6",
            operatingSystemBuild: "25G1",
            deviceModelIdentifier: "Mac16,1",
            modelVariant: "Core 3",
            contextSize: 4_096,
            runtime: .onDevice,
            localeIdentifier: "en_US"
        )
    }
}
