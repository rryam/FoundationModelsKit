import Foundation

/// Codable text-generation recordings paired with the runtime where they were captured.
public struct FoundationModelTextGenerationCassette: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let fingerprint: FoundationModelRuntimeFingerprint
    public let records: [FoundationModelTextGenerationRecord]

    public init(
        formatVersion: Int = currentFormatVersion,
        fingerprint: FoundationModelRuntimeFingerprint,
        records: [FoundationModelTextGenerationRecord]
    ) {
        self.formatVersion = formatVersion
        self.fingerprint = fingerprint
        self.records = records.sorted { $0.sequence < $1.sequence }
    }
}
