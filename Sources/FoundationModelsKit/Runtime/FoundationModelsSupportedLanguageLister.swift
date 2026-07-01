import Foundation
import FoundationModels

public struct FoundationModelsSupportedLanguageLister: FoundationModelSupportedLanguageListing {
    public init() {}

    public func supportedLanguages(locale: Locale = .current) -> FoundationModelSupportedLanguages {
        supportedLanguages(useCase: .general, locale: locale)
    }

    public func supportedLanguages(
        useCase: FoundationModelUseCase = .general,
        locale: Locale = .current
    ) -> FoundationModelSupportedLanguages {
        let model = SystemLanguageModel(
            useCase: useCase.foundationModelsValue,
            guardrails: FoundationModelGuardrails.default.foundationModelsValue
        )
        let languages = model.supportedLanguages.map { language in
            FoundationModelSupportedLanguage(
                identifier: language.maximalIdentifier,
                languageCode: language.languageCode?.identifier ?? "",
                regionCode: language.region?.identifier
            )
        }

        return FoundationModelSupportedLanguages(
            languages: languages,
            metadata: FoundationModelExecutionMetadata(
                provider: "Foundation Models",
                modelIdentifier: useCase.rawValue
            )
        )
    }
}
