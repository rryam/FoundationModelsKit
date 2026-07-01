import Foundation

public struct FoundationModelSupportedLanguage: Sendable, Hashable, Codable, Identifiable {
    public let identifier: String
    public let languageCode: String
    public let regionCode: String?

    public var id: String { identifier }

    public init(identifier: String, languageCode: String, regionCode: String?) {
        self.identifier = identifier
        self.languageCode = languageCode
        self.regionCode = regionCode
    }
}

public struct FoundationModelSupportedLanguages: FoundationModelCapabilityResult, Sendable, Hashable, Codable {
    public let languages: [FoundationModelSupportedLanguage]
    public let metadata: FoundationModelExecutionMetadata

    public init(
        languages: [FoundationModelSupportedLanguage],
        metadata: FoundationModelExecutionMetadata = FoundationModelExecutionMetadata()
    ) {
        self.languages = languages
        self.metadata = metadata
    }
}

public extension FoundationModelSupportedLanguage {
    func displayName(in locale: Locale = .current) -> String {
        let languageName = locale.localizedString(forLanguageCode: languageCode) ?? languageCode

        if let regionCode, !regionCode.isEmpty {
            return "\(languageName) (\(languageCode)-\(regionCode))"
        }

        return languageName
    }
}
