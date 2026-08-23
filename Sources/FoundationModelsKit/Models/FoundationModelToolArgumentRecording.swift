import Foundation

/// Controls whether a tool-result router retains generated arguments.
public enum FoundationModelToolArgumentRecording: String, Codable, Equatable, Sendable {
    /// Store only a deterministic fingerprint. This is the default.
    case fingerprintOnly

    /// Store the complete generated argument value alongside its fingerprint when it is valid JSON.
    /// Unencodable rejected arguments are always omitted.
    case includeArguments
}
