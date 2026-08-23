import Foundation
import FoundationModelsKit

/// Records explicit text-generation requests and stable outcomes while forwarding to a real provider.
public actor FoundationModelRecordingTextGenerator: FoundationModelTextGenerating {
    public typealias ErrorProjector = @Sendable (any Error) -> FoundationModelErrorProjection?

    private let base: any FoundationModelTextGenerating
    private let errorProjector: ErrorProjector
    private var nextSequence = 0
    private var recordedResults: [FoundationModelTextGenerationRecord] = []

    public init(
        base: any FoundationModelTextGenerating,
        errorProjector: @escaping ErrorProjector = FoundationModelErrorProjection.project
    ) {
        self.base = base
        self.errorProjector = errorProjector
    }

    public func generateText(
        for request: FoundationModelTextGenerationRequest
    ) async throws -> FoundationModelTextGenerationResult {
        let sequence = nextSequence
        nextSequence += 1

        do {
            let result = try await base.generateText(for: request)
            recordedResults.append(FoundationModelTextGenerationRecord(
                sequence: sequence,
                request: request,
                outcome: .success(result)
            ))
            return result
        } catch is CancellationError {
            recordedResults.append(FoundationModelTextGenerationRecord(
                sequence: sequence,
                request: request,
                outcome: .cancelled
            ))
            throw CancellationError()
        } catch {
            recordedResults.append(FoundationModelTextGenerationRecord(
                sequence: sequence,
                request: request,
                outcome: .failure(
                    errorProjector(error) ?? FoundationModelErrorProjection(category: .unknown)
                )
            ))
            throw error
        }
    }

    /// Returns recordings in request-start order, even if concurrent requests finish out of order.
    public func records() -> [FoundationModelTextGenerationRecord] {
        recordedResults.sorted { $0.sequence < $1.sequence }
    }

    /// Packages current recordings with public runtime metadata for export or replay.
    public func cassette(
        fingerprint: FoundationModelRuntimeFingerprint = .current
    ) -> FoundationModelTextGenerationCassette {
        FoundationModelTextGenerationCassette(
            fingerprint: fingerprint,
            records: recordedResults
        )
    }
}
