import Foundation

public enum FoundationModelUseCase: String, Sendable, Hashable, Codable, CaseIterable {
    case general
    case contentTagging = "content-tagging"
}
