import Foundation
import FoundationModels

public struct FoundationModelsTextGenerator: FoundationModelTextGenerating {
    public let imageAttachmentPolicy: FoundationModelImageAttachmentPolicy

    public init() {
        self.init(imageAttachmentPolicy: .default)
    }

    public init(imageAttachmentPolicy: FoundationModelImageAttachmentPolicy) {
        self.imageAttachmentPolicy = imageAttachmentPolicy
    }

    public func generateText(
        for request: FoundationModelTextGenerationRequest
    ) async throws -> FoundationModelTextGenerationResult {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw FoundationModelsKitError.invalidRequest("Missing prompt")
        }

        let responsePrompt = try makePrompt(
            text: prompt,
            attachments: request.imageAttachments
        )
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
                to: responsePrompt,
                options: generationOptions.foundationModelsValue
            ).content
        } else {
            responseContent = try await session.respond(to: responsePrompt).content
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

    private func makePrompt(
        text: String,
        attachments: [FoundationModelImageAttachment]
    ) throws -> Prompt {
        guard !attachments.isEmpty else {
            return Prompt(text)
        }

        #if compiler(>=6.4)
        guard #available(iOS 27.0, macOS 27.0, *) else {
            throw FoundationModelsKitError.unavailableCapability(
                "Image prompting requires iOS 27 or macOS 27"
            )
        }
        try FoundationModelImageAttachmentInspector(
            policy: imageAttachmentPolicy
        ).validateForExecution(attachments)

        return Prompt {
            text
            for attachment in attachments {
                if let imageURL = attachment.imageURL {
                    Attachment(
                        imageURL: imageURL,
                        orientation: attachment.orientation?.foundationModelsValue
                    )
                    .label(attachment.label)
                }
            }
        }
        #else
        throw FoundationModelsKitError.unavailableCapability(
            "Image prompting requires the Xcode 27 SDK"
        )
        #endif
    }
}

#if compiler(>=6.4)
import ImageIO

extension FoundationModelImageAttachment.Orientation {
    @available(iOS 27.0, macOS 27.0, *)
    fileprivate var foundationModelsValue: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        case .left: .left
        }
    }
}
#endif
