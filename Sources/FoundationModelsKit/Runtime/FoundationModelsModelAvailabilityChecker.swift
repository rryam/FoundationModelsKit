import Foundation
import FoundationModels

public struct FoundationModelsModelAvailabilityChecker: FoundationModelAvailabilityChecking {
    public init() {}

    public func currentAvailability() -> FoundationModelAvailability {
        currentAvailability(useCase: .general)
    }

    public func currentAvailability(
        useCase: FoundationModelUseCase = .general
    ) -> FoundationModelAvailability {
        let model = SystemLanguageModel(
            useCase: useCase.foundationModelsValue,
            guardrails: FoundationModelGuardrails.default.foundationModelsValue
        )
        return FoundationModelsModelFactory.availabilityResult(
            for: model,
            modelIdentifier: useCase.rawValue
        )
    }
}
