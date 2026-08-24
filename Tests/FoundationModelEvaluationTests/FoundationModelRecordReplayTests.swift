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

    @Test("Replay remains compatible with format 1 text-only cassettes")
    func replaysFormatOneCassette() async throws {
        let result = FoundationModelTextGenerationResult(content: "legacy")
        let cassette = FoundationModelTextGenerationCassette(
            formatVersion: 1,
            fingerprint: testFingerprint,
            records: [
                FoundationModelTextGenerationRecord(
                    sequence: 0,
                    request: request(correlationID: UUID()),
                    outcome: .success(result)
                )
            ]
        )

        let replay = try FoundationModelReplayTextGenerator(cassette: cassette)

        #expect(try await replay.generateText(
            for: request(correlationID: UUID())
        ) == result)
    }

    @Test("Recorder replaces image paths with metadata and replay matches image content")
    func redactsAndReplaysImageAttachments() async throws {
        let recordedURL = try temporaryEvaluationPNG(named: "private-original.png")
        let replayURL = try temporaryEvaluationPNG(named: "renamed-copy.png")
        defer {
            removeTemporaryEvaluationItem(containing: recordedURL)
            removeTemporaryEvaluationItem(containing: replayURL)
        }
        let result = FoundationModelTextGenerationResult(content: "image result")
        let recorder = FoundationModelRecordingTextGenerator(
            base: ScriptedTextGenerator(outcomes: [.success(result)])
        )
        let recordedRequest = request(
            correlationID: UUID(),
            imageAttachments: [
                FoundationModelImageAttachment(
                    label: "subject",
                    imageURL: recordedURL
                )
            ]
        )

        _ = try await recorder.generateText(for: recordedRequest)
        let cassette = await recorder.cassette(fingerprint: testFingerprint)
        let encoded = try JSONEncoder().encode(cassette)
        let json = try #require(String(data: encoded, encoding: .utf8))
        let recordedAttachment = try #require(
            cassette.records.first?.request.imageAttachments.first
        )

        #expect(recordedAttachment.imageURL == nil)
        #expect(recordedAttachment.descriptor?.sha256Digest.count == 64)
        #expect(!json.contains(recordedURL.path()))
        #expect(!json.contains("private-original.png"))

        let replay = try FoundationModelReplayTextGenerator(cassette: cassette)
        let replayRequest = request(
            correlationID: UUID(),
            imageAttachments: [
                FoundationModelImageAttachment(
                    label: "subject",
                    imageURL: replayURL
                )
            ]
        )

        #expect(try await replay.generateText(for: replayRequest) == result)
    }

    @Test("Replay rejects different image content and malformed recorded metadata")
    func rejectsMismatchedImageContent() async throws {
        let imageURL = try temporaryEvaluationPNG(named: "original.png")
        let differentURL = try temporaryEvaluationFile(
            named: "different.png",
            data: try #require(Data(base64Encoded: differentEvaluationPNGBase64))
        )
        defer {
            removeTemporaryEvaluationItem(containing: imageURL)
            removeTemporaryEvaluationItem(containing: differentURL)
        }
        let result = FoundationModelTextGenerationResult(content: "image result")
        let recorder = FoundationModelRecordingTextGenerator(
            base: ScriptedTextGenerator(outcomes: [.success(result)])
        )
        _ = try await recorder.generateText(for: request(
            correlationID: UUID(),
            imageAttachments: [
                FoundationModelImageAttachment(label: "subject", imageURL: imageURL)
            ]
        ))
        let cassette = await recorder.cassette(fingerprint: testFingerprint)
        let replay = try FoundationModelReplayTextGenerator(cassette: cassette)

        await #expect(throws: FoundationModelReplayError.self) {
            _ = try await replay.generateText(for: request(
                correlationID: UUID(),
                imageAttachments: [
                    FoundationModelImageAttachment(label: "subject", imageURL: differentURL)
                ]
            ))
        }

        let malformed = FoundationModelImageAttachment.metadataOnly(
            FoundationModelImageAttachmentDescriptor(
                label: "subject",
                contentTypeIdentifier: "public.png",
                byteCount: 1,
                sha256Digest: "not-a-digest"
            )
        )
        let malformedCassette = FoundationModelTextGenerationCassette(
            fingerprint: testFingerprint,
            records: [
                FoundationModelTextGenerationRecord(
                    sequence: 0,
                    request: request(
                        correlationID: UUID(),
                        imageAttachments: [malformed]
                    ),
                    outcome: .success(result)
                )
            ]
        )

        #expect(throws: FoundationModelsKitError.self) {
            _ = try FoundationModelReplayTextGenerator(cassette: malformedCassette)
        }
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

    private func request(
        correlationID: UUID,
        imageAttachments: [FoundationModelImageAttachment] = []
    ) -> FoundationModelTextGenerationRequest {
        FoundationModelTextGenerationRequest(
            prompt: "Prompt",
            systemPrompt: "Instructions",
            generationOptions: FoundationModelGenerationOptions(temperature: 0.2),
            imageAttachments: imageAttachments,
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

private let evaluationPNGBase64 = """
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=
"""

private let differentEvaluationPNGBase64 = """
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z8i8AAAAASUVORK5CYII=
"""

private func temporaryEvaluationPNG(named name: String) throws -> URL {
    try temporaryEvaluationFile(
        named: name,
        data: try #require(Data(base64Encoded: evaluationPNGBase64))
    )
}

private func temporaryEvaluationFile(named name: String, data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "FoundationModelEvaluationTests-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let url = directory.appending(path: name)
    try data.write(to: url, options: .atomic)
    return url
}

private func removeTemporaryEvaluationItem(containing url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
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
