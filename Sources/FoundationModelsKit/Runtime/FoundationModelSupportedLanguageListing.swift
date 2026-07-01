import Foundation

public protocol FoundationModelSupportedLanguageListing: Sendable {
    func supportedLanguages(locale: Locale) -> FoundationModelSupportedLanguages
    func supportedLanguages(
        useCase: FoundationModelUseCase,
        locale: Locale
    ) -> FoundationModelSupportedLanguages
}

public extension FoundationModelSupportedLanguageListing {
    func supportedLanguages(
        useCase _: FoundationModelUseCase,
        locale: Locale
    ) -> FoundationModelSupportedLanguages {
        supportedLanguages(locale: locale)
    }
}
