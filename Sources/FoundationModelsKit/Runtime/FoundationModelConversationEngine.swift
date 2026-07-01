import Foundation
import FoundationModels

@MainActor
public final class FoundationModelConversationEngine {
    public var onStateChange: (@MainActor () -> Void)?
    public private(set) var session: LanguageModelSession
    public private(set) var sessionCount: Int = 1
    public private(set) var currentTokenCount: Int = 0
    public private(set) var currentTokenUsage: ModelTokenUsage?
    public private(set) var maxContextSize: Int
    public private(set) var isSummarizing: Bool = false
    public private(set) var isApplyingWindow: Bool = false
    public var modelRuntime: FoundationModelRuntime {
        configuration.modelRuntime
    }
    public var reasoningLevel: FoundationModelReasoningLevel {
        configuration.reasoningLevel
    }
    public var guardrails: FoundationModelGuardrails {
        configuration.guardrails
    }
    var currentSessionInstructions: String {
        sessionInstructions
    }
    var effectiveTargetWindowSize: Int {
        max(1, min(configuration.targetWindowSize, maxContextSize))
    }
    private var configuration: FoundationModelConversationConfiguration
    private var model: SystemLanguageModel
    private var sessionInstructions: String
    private let adapterURL: URL?
    private var activeStreamingTask: Task<String, Error>?
    private var activeResponseID: UUID?

    public convenience init(configuration: FoundationModelConversationConfiguration) {
        self.init(
            configuration: configuration,
            model: SystemLanguageModel(
                useCase: configuration.modelUseCase.foundationModelsValue,
                guardrails: configuration.guardrails.foundationModelsValue
            ),
            adapterURL: nil
        )
    }

    public convenience init(
        configuration: FoundationModelConversationConfiguration,
        adapterURL: URL
    ) throws {
        guard configuration.modelRuntime == .onDevice else {
            throw FoundationModelsKitError.invalidRequest(
                "Foundation Models adapters only support the on-device runtime."
            )
        }
        guard configuration.reasoningLevel == .none else {
            throw FoundationModelsKitError.invalidRequest(
                "Foundation Models adapters do not support Private Cloud Compute reasoning levels."
            )
        }
        self.init(
            configuration: configuration,
            model: try FoundationModelsModelFactory.makeModel(
                guardrails: configuration.guardrails,
                adapterURL: adapterURL
            ),
            adapterURL: adapterURL
        )
    }

    init(
        configuration: FoundationModelConversationConfiguration,
        model: SystemLanguageModel,
        adapterURL: URL?
    ) {
        self.configuration = configuration
        self.model = model
        self.sessionInstructions = configuration.baseInstructions
        self.adapterURL = adapterURL
        self.maxContextSize = configuration.defaultMaxContextSize
        self.session = FoundationModelSessionFactory.makeSession(
            runtime: configuration.modelRuntime,
            model: model,
            tools: configuration.tools,
            instructions: sessionInstructions
        )
    }

    public func setMaxContextSize(_ value: Int) {
        guard value > 0 else { return }
        maxContextSize = value
        notifyStateChange()
    }
    public func setReasoningLevel(_ level: FoundationModelReasoningLevel) {
        guard configuration.reasoningLevel != level else { return }
        configuration.reasoningLevel = level
        notifyStateChange()
    }

    public func rebuild(
        baseInstructions: String? = nil,
        modelRuntime: FoundationModelRuntime? = nil,
        reasoningLevel: FoundationModelReasoningLevel? = nil,
        guardrails: FoundationModelGuardrails? = nil,
        tools: [any Tool]? = nil
    ) {
        if let baseInstructions {
            configuration.baseInstructions = baseInstructions
            sessionInstructions = baseInstructions
        }
        if let modelRuntime, adapterURL == nil {
            configuration.modelRuntime = modelRuntime
        }
        if let reasoningLevel, adapterURL == nil {
            configuration.reasoningLevel = reasoningLevel
        }
        if let guardrails, adapterURL == nil {
            configuration.guardrails = guardrails
        }
        if let tools {
            configuration.tools = tools
        }
        if adapterURL != nil {
            configuration.modelRuntime = .onDevice
            configuration.reasoningLevel = .none
            configuration.guardrails = .default
        }

        if adapterURL == nil {
            model = SystemLanguageModel(
                useCase: configuration.modelUseCase.foundationModelsValue,
                guardrails: configuration.guardrails.foundationModelsValue
            )
        }
        resetSession()
    }

    public func clear() {
        resetSession()
    }
    public func cancelActiveResponse() {
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        activeResponseID = nil
    }

    func applyRecoveredConversationSummary(_ summary: FoundationModelConversationSummary) {
        let contextInstructions = FoundationModelConversationContextBuilder.contextInstructions(
            baseInstructions: configuration.baseInstructions,
            summary: summary,
            continuationNote: configuration.continuationNote
        )
        sessionInstructions = contextInstructions

        session = FoundationModelSessionFactory.makeSession(
            runtime: configuration.modelRuntime,
            model: model,
            tools: configuration.tools,
            instructions: sessionInstructions
        )
        sessionCount += 1
        currentTokenCount = 0
        currentTokenUsage = nil
        notifyStateChange()
    }

    public func prewarm(promptPrefix: Prompt? = nil) {
        if let promptPrefix {
            session.prewarm(promptPrefix: promptPrefix)
        } else {
            session.prewarm()
        }
    }
    public func prewarm(withPromptPrefix promptPrefix: String?) {
        let trimmedPrefix = promptPrefix?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedPrefix, !trimmedPrefix.isEmpty {
            session.prewarm(promptPrefix: Prompt(trimmedPrefix))
        } else {
            session.prewarm()
        }
    }

    public func sendStreamingMessage(
        _ content: String,
        generationOptions: FoundationModelGenerationOptions? = nil,
        onPartialResponse: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let prompt = try validatedPrompt(from: content)
        do {
            if await shouldApplyWindow() {
                await applySlidingWindow()
            }

            let response = try await streamResponse(
                to: prompt,
                generationOptions: generationOptions,
                onPartialResponse: onPartialResponse
            )
            await updateTokenCount()
            return response
        } catch where FoundationModelErrorProjection.isContextOverflow(error) {
            return try await recoverFromContextOverflow(
                userMessage: prompt,
                generationOptions: generationOptions,
                responseMode: .streaming,
                onPartialResponse: onPartialResponse
            )
        }
    }

    public func sendMessage(
        _ content: String,
        generationOptions: FoundationModelGenerationOptions? = nil
    ) async throws -> String {
        let prompt = try validatedPrompt(from: content)
        do {
            if await shouldApplyWindow() {
                await applySlidingWindow()
            }

            let response = try await oneShotResponse(
                to: prompt,
                generationOptions: generationOptions
            )
            await updateTokenCount()
            return response
        } catch where FoundationModelErrorProjection.isContextOverflow(error) {
            return try await recoverFromContextOverflow(
                userMessage: prompt,
                generationOptions: generationOptions,
                responseMode: .oneShot,
                onPartialResponse: nil
            )
        }
    }
}

private extension FoundationModelConversationEngine {
    enum ResponseMode {
        case streaming
        case oneShot
    }

    func validatedPrompt(from content: String) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FoundationModelsKitError.invalidRequest("Missing prompt")
        }
        return trimmed
    }
    func resetSession() {
        cancelActiveResponse()
        sessionCount = 1
        currentTokenCount = 0
        currentTokenUsage = nil
        isSummarizing = false
        isApplyingWindow = false
        session = FoundationModelSessionFactory.makeSession(
            runtime: configuration.modelRuntime,
            model: model,
            tools: configuration.tools,
            instructions: sessionInstructions
        )
        notifyStateChange()
    }

    func shouldApplyWindow() async -> Bool {
        guard configuration.enableSlidingWindow, configuration.tools.isEmpty, configuration.modelRuntime == .onDevice else {
            return false
        }

        return await session.transcript.isApproachingLimit(
            threshold: configuration.windowThreshold,
            maxTokens: maxContextSize,
            using: model
        )
    }

    func applySlidingWindow() async {
        guard configuration.enableSlidingWindow, configuration.tools.isEmpty, configuration.modelRuntime == .onDevice else {
            return
        }

        isApplyingWindow = true
        notifyStateChange()

        let windowEntries = await session.transcript.entriesWithinTokenBudget(
            effectiveTargetWindowSize,
            using: model
        )
        let transcript = Transcript(entries: windowEntries)

        session = LanguageModelSession(model: model, transcript: transcript)
        sessionCount += 1
        await updateTokenCount(usageSource: .context)

        isApplyingWindow = false
        notifyStateChange()
    }

    func updateTokenCount(usageSource: FoundationModelConversationTokenUsageSource = .accumulatedSession) async {
        let snapshot = await foundationModelConversationTokenSnapshot(
            session: session,
            model: model,
            runtime: configuration.modelRuntime,
            usageSource: usageSource
        )
        currentTokenCount = snapshot.legacyTokenCount
        currentTokenUsage = snapshot.usage
        notifyStateChange()
    }

    func streamResponse(
        to prompt: String,
        generationOptions: FoundationModelGenerationOptions?,
        onPartialResponse: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        activeStreamingTask?.cancel()
        let transcriptCountBeforeResponse = session.transcript.count
        let task = Task<String, Error> { @MainActor [weak self] in
            guard let self else {
                throw CancellationError()
            }

            let latest = try await self.performStreamingResponse(
                to: prompt,
                generationOptions: generationOptions,
                onPartialResponse: onPartialResponse
            )
            try Task.checkCancellation()
            return latest.isEmpty
                ? self.session.transcript.latestResponseText(after: transcriptCountBeforeResponse)
                : latest
        }

        let responseID = UUID()
        activeStreamingTask = task
        activeResponseID = responseID
        defer {
            if activeResponseID == responseID {
                activeStreamingTask = nil
                activeResponseID = nil
            }
        }
        return try await task.valuePropagatingCancellation()
    }

    func performStreamingResponse(
        to prompt: String,
        generationOptions: FoundationModelGenerationOptions?,
        onPartialResponse: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        if let generationOptions {
            return try await streamWithGenerationOptions(
                prompt: prompt,
                generationOptions: generationOptions,
                onPartialResponse: onPartialResponse
            )
        }

        return try await streamWithoutGenerationOptions(
            prompt: prompt,
            onPartialResponse: onPartialResponse
        )
    }

    func oneShotResponse(
        to prompt: String,
        generationOptions: FoundationModelGenerationOptions?
    ) async throws -> String {
        activeStreamingTask?.cancel()
        let task = Task<String, Error> { @MainActor [weak self] in
            guard let self else {
                throw CancellationError()
            }
            let response = try await self.respond(to: prompt, generationOptions: generationOptions)
            try Task.checkCancellation()
            return response
        }

        let responseID = UUID()
        activeStreamingTask = task
        activeResponseID = responseID
        defer {
            if activeResponseID == responseID {
                activeStreamingTask = nil
                activeResponseID = nil
            }
        }
        return try await task.valuePropagatingCancellation()
    }

    func streamWithGenerationOptions(
        prompt: String,
        generationOptions: FoundationModelGenerationOptions,
        onPartialResponse: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        var latest = ""
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *),
           let contextOptions = contextOptions() {
            for try await snapshot in session.streamResponse(
                to: Prompt(prompt),
                options: generationOptions.foundationModelsValue,
                contextOptions: contextOptions
            ) {
                latest = snapshot.content
                onPartialResponse?(snapshot.content)
            }
            return latest
        }
        #endif

        for try await snapshot in session.streamResponse(
            to: Prompt(prompt),
            options: generationOptions.foundationModelsValue
        ) {
            latest = snapshot.content
            onPartialResponse?(snapshot.content)
        }
        return latest
    }

    func streamWithoutGenerationOptions(
        prompt: String,
        onPartialResponse: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        var latest = ""
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *),
           let contextOptions = contextOptions() {
            for try await snapshot in session.streamResponse(
                to: Prompt(prompt),
                contextOptions: contextOptions
            ) {
                latest = snapshot.content
                onPartialResponse?(snapshot.content)
            }
            return latest
        }
        #endif

        for try await snapshot in session.streamResponse(to: Prompt(prompt)) {
            latest = snapshot.content
            onPartialResponse?(snapshot.content)
        }
        return latest
    }

    func respond(
        to prompt: String,
        generationOptions: FoundationModelGenerationOptions?
    ) async throws -> String {
        if let generationOptions {
            #if compiler(>=6.4)
            if #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *) {
                if let contextOptions = contextOptions() {
                    return try await session.respond(
                        to: Prompt(prompt),
                        options: generationOptions.foundationModelsValue,
                        contextOptions: contextOptions
                    ).content
                }

                return try await session.respond(
                    to: Prompt(prompt),
                    options: generationOptions.foundationModelsValue
                ).content
            }
            #endif

            return try await session.respond(
                to: Prompt(prompt),
                options: generationOptions.foundationModelsValue
            ).content
        }

        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *) {
            if let contextOptions = contextOptions() {
                return try await session.respond(
                    to: Prompt(prompt),
                    contextOptions: contextOptions
                ).content
            }

            return try await session.respond(
                to: Prompt(prompt)
            ).content
        }
        #endif

        return try await session.respond(to: Prompt(prompt)).content
    }

    func recoverFromContextOverflow(
        userMessage: String,
        generationOptions: FoundationModelGenerationOptions?,
        responseMode: ResponseMode,
        onPartialResponse: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        isSummarizing = true
        notifyStateChange()

        defer {
            isSummarizing = false
            notifyStateChange()
        }

        do {
            let summary = try await generateConversationSummary()
            applyRecoveredConversationSummary(summary)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            createFreshSessionAfterOverflow()

            if let overflowResetMessage = trimmedOverflowResetMessage() {
                onPartialResponse?(overflowResetMessage)
                return overflowResetMessage
            }

            throw error
        }

        let response: String
        switch responseMode {
        case .streaming:
            response = try await streamResponse(
                to: userMessage,
                generationOptions: generationOptions,
                onPartialResponse: onPartialResponse
            )
        case .oneShot:
            response = try await respond(to: userMessage, generationOptions: generationOptions)
        }

        await updateTokenCount()
        return response
    }

    func generateConversationSummary() async throws -> FoundationModelConversationSummary {
        let summarySession = FoundationModelSessionFactory.makeSession(
            runtime: .onDevice,
            model: model,
            tools: [],
            instructions: configuration.summaryInstructions
        )

        let conversationText = FoundationModelConversationContextBuilder.conversationText(
            from: session.transcript,
            userLabel: configuration.conversationUserLabel,
            assistantLabel: configuration.conversationAssistantLabel
        )
        let summaryPrompt = """
        \(configuration.summaryPromptPreamble)

        \(conversationText)
        """

        let summaryResponse = try await summarySession.respond(
            to: Prompt(summaryPrompt),
            generating: FoundationModelConversationSummary.self
        )

        return summaryResponse.content
    }

    func createFreshSessionAfterOverflow() {
        sessionInstructions = configuration.baseInstructions
        session = FoundationModelSessionFactory.makeSession(
            runtime: configuration.modelRuntime,
            model: model,
            tools: configuration.tools,
            instructions: sessionInstructions
        )
        sessionCount += 1
        currentTokenCount = 0
        currentTokenUsage = nil
        notifyStateChange()
    }

    func trimmedOverflowResetMessage() -> String? {
        guard let message = configuration.overflowResetMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        return message
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    func contextOptions() -> ContextOptions? {
        guard configuration.modelRuntime == .privateCloudCompute,
              configuration.reasoningLevel != .none else {
            return nil
        }

        return ContextOptions(reasoningLevel: configuration.reasoningLevel.foundationModelsValue)
    }
    #endif

    func notifyStateChange() {
        onStateChange?()
    }
}
