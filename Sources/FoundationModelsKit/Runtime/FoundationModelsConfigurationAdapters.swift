import Foundation
import FoundationModels

extension FoundationModelUseCase {
    public var foundationModelsValue: SystemLanguageModel.UseCase {
        switch self {
        case .general:
            return .general
        case .contentTagging:
            return .contentTagging
        }
    }
}

extension FoundationModelGuardrails {
    public var foundationModelsValue: SystemLanguageModel.Guardrails {
        switch self {
        case .default:
            return .default
        case .permissiveContentTransformations:
            return .permissiveContentTransformations
        }
    }
}

extension FoundationModelGenerationOptions.SamplingMode {
    public var foundationModelsValue: GenerationOptions.SamplingMode {
        switch self {
        case .greedy:
            return .greedy
        case .randomTop(let top, let seed):
            return .random(top: top, seed: seed)
        case .randomProbabilityThreshold(let threshold, let seed):
            return .random(probabilityThreshold: threshold, seed: seed)
        }
    }
}

extension FoundationModelGenerationOptions {
    public var foundationModelsValue: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(
            samplingMode: sampling?.foundationModelsValue,
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
        )
        #else
        GenerationOptions(
            sampling: sampling?.foundationModelsValue,
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
        )
        #endif
    }
}

#if compiler(>=6.4)
extension FoundationModelReasoningLevel {
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    var foundationModelsValue: ContextOptions.ReasoningLevel? {
        switch self {
        case .none:
            return nil
        case .light:
            return .light
        case .moderate:
            return .moderate
        case .deep:
            return .deep
        }
    }
}
#endif
