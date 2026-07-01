import Foundation
import FoundationModels

public struct FoundationModelsTextGenerator: FoundationModelTextGenerating {
    public init() {}

    public func generateText(for request: FoundationModelTextGenerationRequest) async throws -> FoundationModelTextGenerationResult {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw FoundationModelsKitError.invalidRequest("Missing prompt")
        }

        let model = try FoundationModelsModelFactory.makeModel(
            useCase: request.modelUseCase,
            guardrails: request.guardrails ?? .default,
            adapterURL: request.adapterURL
        )
        let session: LanguageModelSession

        if let systemPrompt = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !systemPrompt.isEmpty {
            session = LanguageModelSession(
                model: model,
                instructions: Instructions(systemPrompt)
            )
        } else {
            session = LanguageModelSession(model: model)
        }

        let responseContent: String
        if let generationOptions = request.generationOptions {
            responseContent = try await session.respond(
                to: Prompt(prompt),
                options: generationOptions.foundationModelsValue
            ).content
        } else {
            responseContent = try await session.respond(to: Prompt(prompt)).content
        }

        let tokenCount = await session.transcript.tokenCount(using: model)

        return FoundationModelTextGenerationResult(
            content: responseContent,
            metadata: FoundationModelExecutionMetadata(
                provider: "Foundation Models",
                modelIdentifier: request.adapterURL?.lastPathComponent ?? request.modelUseCase.rawValue,
                tokenCount: tokenCount
            )
        )
    }
}
