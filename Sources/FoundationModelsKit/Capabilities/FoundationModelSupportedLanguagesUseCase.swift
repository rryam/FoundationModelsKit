import Foundation

public struct FoundationModelSupportedLanguagesUseCase: Sendable {
    public static let descriptor = FoundationModelCapabilityDescriptor(
        id: "foundation-models.list-supported-languages",
        displayName: "List Supported Languages",
        summary: "Lists the languages supported by the current Foundation Models runtime."
    )

    private let lister: any FoundationModelSupportedLanguageListing

    public init(lister: any FoundationModelSupportedLanguageListing = FoundationModelsSupportedLanguageLister()) {
        self.lister = lister
    }

    public func execute(
        useCase: FoundationModelUseCase = .general,
        locale: Locale = .current
    ) -> FoundationModelSupportedLanguages {
        lister.supportedLanguages(useCase: useCase, locale: locale)
    }
}
