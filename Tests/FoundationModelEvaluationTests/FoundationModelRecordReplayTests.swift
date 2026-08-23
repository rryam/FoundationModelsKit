import Foundation
import FoundationModelEvaluation
import FoundationModelsKit
import Testing

@Suite("Foundation Model record and replay")
struct FoundationModelRecordReplayTests {
    @Test("Recorder captures successful output and runtime metadata")
    func recordsSuccess() async throws {
        let result = FoundationModelTextGenerationResult(
            content: "Recorded answer",
            metadata: FoundationModelExecutionMetadata(tokenCount: 4)
        )
        let recorder = FoundationModelRecordingTextGenerator(
            base: ScriptedTextGenerator(outcomes: [.success(result)])
        )

        let observed = try await recorder.generateText(for: request(correlationID: UUID()))
        let cassette = await recorder.cassette(fingerprint: testFingerprint)

        #expect(observed == result)
        #expect(cassette.fingerprint == testFingerprint)
        #expect(cassette.records.count == 1)
        #expect(cassette.records[0].outcome == .success(result))
    }

    @Test("Replay ignores correlation IDs and consumes repeated requests in order")
    func replaysRepeatedRequests() async throws {
        let first = FoundationModelTextGenerationResult(content: "first")
        let second = FoundationModelTextGenerationResult(content: "second")
        let recordedRequest = request(
            correlationID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let cassette = FoundationModelTextGenerationCassette(
            fingerprint: testFingerprint,
            records: [
                FoundationModelTextGenerationRecord(
                    sequence: 0,
                    request: recordedRequest,
                    outcome: .success(first)
                ),
                FoundationModelTextGenerationRecord(
                    sequence: 1,
                    request: recordedRequest,
                    outcome: .success(second)
                )
            ]
        )
        let replay = try FoundationModelReplayTextGenerator(cassette: cassette)
        let replayRequest = request(
            correlationID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )

        #expect(try await replay.generateText(for: replayRequest) == first)
        #expect(try await replay.generateText(for: replayRequest) == second)
        await #expect(throws: FoundationModelReplayError.self) {
            _ = try await replay.generateText(for: replayRequest)
        }
        #expect(await replay.consumedRecordCount() == 2)
    }

    @Test("Recorded failures keep their projected category during replay")
    func replaysProjectedFailure() async throws {
        let cassette = FoundationModelTextGenerationCassette(
            fingerprint: testFingerprint,
            records: [
                FoundationModelTextGenerationRecord(
                    sequence: 0,
                    request: request(correlationID: UUID()),
                    outcome: .failure(
                        FoundationModelErrorProjection(category: .rateLimited)
                    )
                )
            ]
        )
        let replay = try FoundationModelReplayTextGenerator(cassette: cassette)

        do {
            _ = try await replay.generateText(for: request(correlationID: UUID()))
            Issue.record("Expected the recorded failure")
        } catch {
            #expect(FoundationModelErrorProjection.project(error)?.category == .rateLimited)
        }
    }

    @Test("Replay preserves recorded cancellation")
    func replaysCancellation() async throws {
        let cassette = FoundationModelTextGenerationCassette(
            fingerprint: testFingerprint,
            records: [
                FoundationModelTextGenerationRecord(
                    sequence: 0,
                    request: request(correlationID: UUID()),
                    outcome: .cancelled
                )
            ]
        )
        let replay = try FoundationModelReplayTextGenerator(cassette: cassette)

        await #expect(throws: CancellationError.self) {
            _ = try await replay.generateText(for: request(correlationID: UUID()))
        }
    }

    @Test("Cassettes round-trip requests and responses")
    func cassetteRoundTrips() throws {
        let cassette = FoundationModelTextGenerationCassette(
            fingerprint: testFingerprint,
            records: [
                FoundationModelTextGenerationRecord(
                    sequence: 0,
                    request: request(correlationID: UUID()),
                    outcome: .success(FoundationModelTextGenerationResult(content: "answer"))
                )
            ]
        )

        let data = try JSONEncoder().encode(cassette)
        let decoded = try JSONDecoder().decode(
            FoundationModelTextGenerationCassette.self,
            from: data
        )

        #expect(decoded == cassette)
    }

    @Test("Golden comparisons exclude timing and report stable field drift")
    func comparesStableEvaluationFields() {
        let firstTrace = trace(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 101),
            finalSuccess: true
        )
        let timingOnlyTrace = trace(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 200),
            finishedAt: Date(timeIntervalSince1970: 250),
            finalSuccess: true
        )
        let failedTrace = trace(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 300),
            finishedAt: Date(timeIntervalSince1970: 301),
            finalSuccess: false
        )
        let expected = FoundationModelEvaluationSnapshot(trace: firstTrace)

        #expect(
            FoundationModelEvaluationComparison(
                expected: expected,
                actual: FoundationModelEvaluationSnapshot(trace: timingOnlyTrace)
            ).passed
        )
        #expect(
            FoundationModelEvaluationComparison(
                expected: expected,
                actual: FoundationModelEvaluationSnapshot(trace: failedTrace)
            ).mismatchedFields == [.finalSuccess]
        )
    }

    private func request(correlationID: UUID) -> FoundationModelTextGenerationRequest {
        FoundationModelTextGenerationRequest(
            prompt: "Prompt",
            systemPrompt: "Instructions",
            generationOptions: FoundationModelGenerationOptions(temperature: 0.2),
            context: FoundationModelInvocationContext(
                source: .automation,
                localeIdentifier: "en_US",
                correlationID: correlationID
            )
        )
    }

    private func trace(
        id: UUID,
        startedAt: Date,
        finishedAt: Date,
        finalSuccess: Bool
    ) -> FoundationModelExecutionTrace {
        FoundationModelExecutionTrace(
            id: id,
            startedAt: startedAt,
            finishedAt: finishedAt,
            fingerprint: testFingerprint,
            latency: FoundationModelLatency(
                total: finishedAt.timeIntervalSince(startedAt)
            ),
            outcome: .completed,
            finalSuccess: finalSuccess
        )
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

private actor ScriptedTextGenerator: FoundationModelTextGenerating {
    enum Outcome: Sendable {
        case success(FoundationModelTextGenerationResult)
        case failure(FoundationModelErrorProjection)
        case cancelled
    }

    private var outcomes: [Outcome]

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func generateText(
        for request: FoundationModelTextGenerationRequest
    ) async throws -> FoundationModelTextGenerationResult {
        _ = request
        guard !outcomes.isEmpty else {
            throw FoundationModelReplayError.recordingExhausted(
                requestFingerprint: "script"
            )
        }
        switch outcomes.removeFirst() {
        case .success(let result):
            return result
        case .failure(let projection):
            throw FoundationModelReplayError.recordedFailure(projection)
        case .cancelled:
            throw CancellationError()
        }
    }
}
