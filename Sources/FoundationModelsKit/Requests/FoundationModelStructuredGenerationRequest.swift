import Foundation
import FoundationModels

public struct FoundationModelStructuredGenerationRequest<Output: Generable & Sendable>: FoundationModelCapabilityRequest, Sendable {
    public let prompt: String
    public let systemPrompt: String?
    public let modelUseCase: FoundationModelUseCase
    public let guardrails: FoundationModelGuardrails?
    public let adapterURL: URL?
    public let generationOptions: FoundationModelGenerationOptions?
    public let includeSchemaInPrompt: Bool
    public let context: FoundationModelInvocationContext

    public init(
        prompt: String,
        systemPrompt: String? = nil,
        modelUseCase: FoundationModelUseCase = .general,
        guardrails: FoundationModelGuardrails? = nil,
        adapterURL: URL? = nil,
        generationOptions: FoundationModelGenerationOptions? = nil,
        includeSchemaInPrompt: Bool = true,
        context: FoundationModelInvocationContext
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.modelUseCase = modelUseCase
        self.guardrails = guardrails
        self.adapterURL = adapterURL
        self.generationOptions = generationOptions
        self.includeSchemaInPrompt = includeSchemaInPrompt
        self.context = context
    }
}
