import Foundation
import FoundationModelsKit

/// A deterministic ``FoundationModelTextGenerating`` fake backed by an exported cassette.
public actor FoundationModelReplayTextGenerator: FoundationModelTextGenerating {
    private struct RequestKey: Codable, Hashable, Sendable {
        let prompt: String
        let systemPrompt: String?
        let modelUseCase: FoundationModelUseCase
        let guardrails: FoundationModelGuardrails?
        let adapterURL: URL?
        let generationOptions: FoundationModelGenerationOptions?
        let imageAttachments: [FoundationModelImageAttachmentDescriptor]
        let source: FoundationModelInvocationSource
        let localeIdentifier: String?

        init(
            request: FoundationModelTextGenerationRequest,
            imageAttachmentInspector: FoundationModelImageAttachmentInspector
        ) throws {
            self.prompt = request.prompt
            self.systemPrompt = request.systemPrompt
            self.modelUseCase = request.modelUseCase
            self.guardrails = request.guardrails
            self.adapterURL = request.adapterURL
            self.generationOptions = request.generationOptions
            self.imageAttachments = try imageAttachmentInspector.descriptors(
                for: request.imageAttachments
            )
            self.source = request.context.source
            self.localeIdentifier = request.context.localeIdentifier
        }
    }

    public nonisolated let fingerprint: FoundationModelRuntimeFingerprint

    private let recordsByKey: [RequestKey: [FoundationModelTextGenerationRecord]]
    private let imageAttachmentInspector: FoundationModelImageAttachmentInspector
    private var consumedCounts: [RequestKey: Int] = [:]

    public init(cassette: FoundationModelTextGenerationCassette) throws {
        try self.init(
            cassette: cassette,
            imageAttachmentPolicy: .default
        )
    }

    public init(
        cassette: FoundationModelTextGenerationCassette,
        imageAttachmentPolicy: FoundationModelImageAttachmentPolicy
    ) throws {
        guard FoundationModelTextGenerationCassette.supportedFormatVersions.contains(
            cassette.formatVersion
        ) else {
            throw FoundationModelReplayError.unsupportedFormatVersion(cassette.formatVersion)
        }

        var seenSequences: Set<Int> = []
        var recordsByKey: [RequestKey: [FoundationModelTextGenerationRecord]] = [:]
        let imageAttachmentInspector = FoundationModelImageAttachmentInspector(
            policy: imageAttachmentPolicy
        )
        for record in cassette.records.sorted(by: { $0.sequence < $1.sequence }) {
            guard record.sequence >= 0 else {
                throw FoundationModelReplayError.invalidSequence(record.sequence)
            }
            guard seenSequences.insert(record.sequence).inserted else {
                throw FoundationModelReplayError.duplicateSequence(record.sequence)
            }
            let key = try RequestKey(
                request: record.request,
                imageAttachmentInspector: imageAttachmentInspector
            )
            recordsByKey[key, default: []].append(record)
        }

        self.fingerprint = cassette.fingerprint
        self.recordsByKey = recordsByKey
        self.imageAttachmentInspector = imageAttachmentInspector
    }

    public func generateText(
        for request: FoundationModelTextGenerationRequest
    ) async throws -> FoundationModelTextGenerationResult {
        let key = try RequestKey(
            request: request,
            imageAttachmentInspector: imageAttachmentInspector
        )
        let fingerprint = try Self.fingerprint(key)
        guard let records = recordsByKey[key] else {
            throw FoundationModelReplayError.noMatchingRecording(
                requestFingerprint: fingerprint
            )
        }

        let index = consumedCounts[key, default: 0]
        guard records.indices.contains(index) else {
            throw FoundationModelReplayError.recordingExhausted(
                requestFingerprint: fingerprint
            )
        }
        consumedCounts[key] = index + 1

        switch records[index].outcome {
        case .success(let result):
            return result
        case .failure(let projection):
            throw FoundationModelReplayError.recordedFailure(projection)
        case .cancelled:
            throw CancellationError()
        }
    }

    /// Returns the number of cassette entries consumed across all semantic request keys.
    public func consumedRecordCount() -> Int {
        consumedCounts.values.reduce(0, +)
    }

    private static func fingerprint(_ key: RequestKey) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(key)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
