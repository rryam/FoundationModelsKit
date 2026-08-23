import Foundation
import FoundationModelsKit

/// A deterministic cassette validation or replay failure.
public enum FoundationModelReplayError: Error, Equatable, Sendable {
    case unsupportedFormatVersion(Int)
    case invalidSequence(Int)
    case duplicateSequence(Int)
    case noMatchingRecording(requestFingerprint: String)
    case recordingExhausted(requestFingerprint: String)
    case recordedFailure(FoundationModelErrorProjection)
}

extension FoundationModelReplayError: FoundationModelProjectedError {
    public var foundationModelErrorProjection: FoundationModelErrorProjection {
        switch self {
        case .recordedFailure(let projection):
            projection
        case .unsupportedFormatVersion,
             .invalidSequence,
             .duplicateSequence,
             .noMatchingRecording,
             .recordingExhausted:
            FoundationModelErrorProjection(category: .unknown)
        }
    }
}
