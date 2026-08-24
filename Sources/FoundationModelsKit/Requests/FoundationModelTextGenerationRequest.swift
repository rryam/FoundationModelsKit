import Foundation
public struct FoundationModelTextGenerationRequest:
    FoundationModelCapabilityRequest,
    Codable,
    Hashable,
    Sendable {
    public let prompt: String
    public let systemPrompt: String?
    public let modelUseCase: FoundationModelUseCase
    public let guardrails: FoundationModelGuardrails?
    public let adapterURL: URL?
    public let generationOptions: FoundationModelGenerationOptions?
    /// Labeled file-backed images for iOS 27 and macOS 27 multimodal prompting.
    public let imageAttachments: [FoundationModelImageAttachment]
    public let context: FoundationModelInvocationContext

    private enum CodingKeys: String, CodingKey {
        case prompt
        case systemPrompt
        case modelUseCase
        case guardrails
        case adapterURL
        case generationOptions
        case imageAttachments
        case context
    }

    public init(
        prompt: String,
        systemPrompt: String? = nil,
        modelUseCase: FoundationModelUseCase = .general,
        guardrails: FoundationModelGuardrails? = nil,
        adapterURL: URL? = nil,
        generationOptions: FoundationModelGenerationOptions? = nil,
        context: FoundationModelInvocationContext
    ) {
        self.init(
            prompt: prompt,
            systemPrompt: systemPrompt,
            modelUseCase: modelUseCase,
            guardrails: guardrails,
            adapterURL: adapterURL,
            generationOptions: generationOptions,
            imageAttachments: [],
            context: context
        )
    }

    public init(
        prompt: String,
        systemPrompt: String? = nil,
        modelUseCase: FoundationModelUseCase = .general,
        guardrails: FoundationModelGuardrails? = nil,
        adapterURL: URL? = nil,
        generationOptions: FoundationModelGenerationOptions? = nil,
        imageAttachments: [FoundationModelImageAttachment],
        context: FoundationModelInvocationContext
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.modelUseCase = modelUseCase
        self.guardrails = guardrails
        self.adapterURL = adapterURL
        self.generationOptions = generationOptions
        self.imageAttachments = imageAttachments
        self.context = context
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try container.decode(String.self, forKey: .prompt)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        modelUseCase = try container.decode(FoundationModelUseCase.self, forKey: .modelUseCase)
        guardrails = try container.decodeIfPresent(FoundationModelGuardrails.self, forKey: .guardrails)
        adapterURL = try container.decodeIfPresent(URL.self, forKey: .adapterURL)
        generationOptions = try container.decodeIfPresent(
            FoundationModelGenerationOptions.self,
            forKey: .generationOptions
        )
        imageAttachments = try container.decodeIfPresent(
            [FoundationModelImageAttachment].self,
            forKey: .imageAttachments
        ) ?? []
        context = try container.decode(FoundationModelInvocationContext.self, forKey: .context)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(systemPrompt, forKey: .systemPrompt)
        try container.encode(modelUseCase, forKey: .modelUseCase)
        try container.encodeIfPresent(guardrails, forKey: .guardrails)
        try container.encodeIfPresent(adapterURL, forKey: .adapterURL)
        try container.encodeIfPresent(generationOptions, forKey: .generationOptions)
        if !imageAttachments.isEmpty {
            try container.encode(imageAttachments, forKey: .imageAttachments)
        }
        try container.encode(context, forKey: .context)
    }

    /// Returns the same semantic request with different image inputs.
    public func replacingImageAttachments(
        with imageAttachments: [FoundationModelImageAttachment]
    ) -> Self {
        Self(
            prompt: prompt,
            systemPrompt: systemPrompt,
            modelUseCase: modelUseCase,
            guardrails: guardrails,
            adapterURL: adapterURL,
            generationOptions: generationOptions,
            imageAttachments: imageAttachments,
            context: context
        )
    }
}
