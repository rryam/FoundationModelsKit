import Foundation
import FoundationModels
import Testing
@testable import FoundationModelsKit

@Suite("Foundation Model Runtime Tests")
struct FoundationModelRuntimeTests {
  @Test("Private Cloud status requires explicit authorization")
  func privateCloudStatusRequiresAuthorization() {
    let missing = FoundationModelRuntimeStatus(
      runtime: .privateCloudCompute,
      isAvailable: true,
      authorization: .missing
    )

    #expect(missing.isRunnableInCurrentProcess == false)
    #expect(missing.reason == .missingEntitlement)

    let granted = FoundationModelRuntimeStatus(
      runtime: .privateCloudCompute,
      isAvailable: true,
      authorization: .granted
    )

    #expect(granted.isRunnableInCurrentProcess == true)
    #expect(granted.reason == nil)
  }

  @Test("Decoded private cloud status recomputes runnable authorization")
  func decodedPrivateCloudStatusRecomputesRunnableAuthorization() throws {
    let data = Data("""
    {
      "runtime": "privateCloudCompute",
      "isSupported": true,
      "isAvailable": true,
      "isRunnableInCurrentProcess": true,
      "authorization": "missing",
      "reason": null,
      "metadata": {}
    }
    """.utf8)

    let status = try JSONDecoder().decode(FoundationModelRuntimeStatus.self, from: data)

    #expect(status.isRunnableInCurrentProcess == false)
    #expect(status.reason == .missingEntitlement)
  }

  @Test("Supported language display names include region when present")
  func supportedLanguageDisplayNameIncludesRegion() {
    let language = FoundationModelSupportedLanguage(
      identifier: "en-US",
      languageCode: "en",
      regionCode: "US"
    )

    #expect(language.displayName(in: Locale(identifier: "en_US")) == "English (en-US)")
  }

  @Test("Adapter conversation engines keep adapter-safe defaults when rebuilding")
  @MainActor
  func adapterConversationEngineKeepsDefaultGuardrailsWhenRebuilding() {
    let engine = FoundationModelConversationEngine(
      configuration: FoundationModelConversationConfiguration(
        baseInstructions: "Answer briefly.",
        summaryInstructions: "Summarize.",
        summaryPromptPreamble: "Summary:",
        conversationUserLabel: "User:",
        conversationAssistantLabel: "Assistant:",
        continuationNote: "Continue."
      ),
      model: .default,
      adapterURL: URL(fileURLWithPath: "/tmp/Test.fmadapter")
    )

    engine.rebuild(
      modelRuntime: .privateCloudCompute,
      reasoningLevel: .deep,
      guardrails: .permissiveContentTransformations
    )

    #expect(engine.modelRuntime == .onDevice)
    #expect(engine.reasoningLevel == .none)
    #expect(engine.guardrails == .default)

    engine.setReasoningLevel(.deep)

    #expect(engine.reasoningLevel == .none)
  }

  @Test("Conversation engine reports resolved runtime")
  @MainActor
  func conversationEngineReportsResolvedRuntime() {
    let engine = FoundationModelConversationEngine(
      configuration: FoundationModelConversationConfiguration(
        baseInstructions: "Answer briefly.",
        summaryInstructions: "Summarize.",
        summaryPromptPreamble: "Summary:",
        conversationUserLabel: "User:",
        conversationAssistantLabel: "Assistant:",
        continuationNote: "Continue.",
        modelRuntime: .privateCloudCompute
      )
    )

    #if compiler(>=6.4)
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *) {
      #expect(engine.modelRuntime == .privateCloudCompute)
    } else {
      #expect(engine.modelRuntime == .onDevice)
    }
    #else
    #expect(engine.modelRuntime == .onDevice)
    #endif
  }

  @Test("Clear preserves recovered summary context")
  @MainActor
  func clearPreservesRecoveredSummaryContext() {
    let engine = FoundationModelConversationEngine(
      configuration: FoundationModelConversationConfiguration(
        baseInstructions: "Answer from the original system prompt.",
        summaryInstructions: "Summarize.",
        summaryPromptPreamble: "Summary:",
        conversationUserLabel: "User:",
        conversationAssistantLabel: "Assistant:",
        continuationNote: "Continue from the summary."
      )
    )
    let summary = FoundationModelConversationSummary(
      summary: "The user is extracting reusable runtime APIs.",
      keyTopics: ["runtime extraction"],
      userPreferences: ["Keep FoundationModelsKit as one package."]
    )

    engine.applyRecoveredConversationSummary(summary)
    let recoveredInstructions = engine.currentSessionInstructions

    #expect(recoveredInstructions.contains("Answer from the original system prompt."))
    #expect(recoveredInstructions.contains("The user is extracting reusable runtime APIs."))

    engine.clear()

    #expect(engine.currentSessionInstructions == recoveredInstructions)

    engine.rebuild(baseInstructions: "Use the new explicit baseline.")

    #expect(engine.currentSessionInstructions == "Use the new explicit baseline.")
  }

  @Test("Sliding window budget does not exceed active context size")
  @MainActor
  func slidingWindowBudgetDoesNotExceedActiveContextSize() {
    let engine = FoundationModelConversationEngine(
      configuration: FoundationModelConversationConfiguration(
        baseInstructions: "Answer briefly.",
        summaryInstructions: "Summarize.",
        summaryPromptPreamble: "Summary:",
        conversationUserLabel: "User:",
        conversationAssistantLabel: "Assistant:",
        continuationNote: "Continue.",
        enableSlidingWindow: true,
        targetWindowSize: 6_000,
        defaultMaxContextSize: 4_096
      )
    )

    #expect(engine.effectiveTargetWindowSize == 4_096)

    engine.setMaxContextSize(1_024)

    #expect(engine.effectiveTargetWindowSize == 1_024)
  }

  @Test("Sliding window budget keeps a positive lower bound")
  @MainActor
  func slidingWindowBudgetKeepsPositiveLowerBound() {
    let engine = FoundationModelConversationEngine(
      configuration: FoundationModelConversationConfiguration(
        baseInstructions: "Answer briefly.",
        summaryInstructions: "Summarize.",
        summaryPromptPreamble: "Summary:",
        conversationUserLabel: "User:",
        conversationAssistantLabel: "Assistant:",
        continuationNote: "Continue.",
        enableSlidingWindow: true,
        targetWindowSize: 0,
        defaultMaxContextSize: 4_096
      )
    )

    #expect(engine.effectiveTargetWindowSize == 1)
  }

  @Test("Sliding window transcript preserves recovered instructions")
  @MainActor
  func slidingWindowTranscriptPreservesRecoveredInstructions() {
    let engine = FoundationModelConversationEngine(
      configuration: FoundationModelConversationConfiguration(
        baseInstructions: "Answer from the original system prompt.",
        summaryInstructions: "Summarize.",
        summaryPromptPreamble: "Summary:",
        conversationUserLabel: "User:",
        conversationAssistantLabel: "Assistant:",
        continuationNote: "Continue from the summary."
      )
    )
    let summary = FoundationModelConversationSummary(
      summary: "The user is extracting reusable runtime APIs.",
      keyTopics: ["runtime extraction"],
      userPreferences: ["Keep FoundationModelsKit as one package."]
    )

    engine.applyRecoveredConversationSummary(summary)

    let transcript = engine.slidingWindowTranscript(from: [
      .instructions(.foundationModelsKitTest("Stale instructions")),
      .prompt(.foundationModelsKitTest("Latest prompt"))
    ])
    let entries = Array(transcript)

    guard case .instructions(let instructions) = entries.first else {
      Issue.record("Expected sliding window transcript to start with instructions")
      return
    }

    #expect(instructions.foundationModelsKitTestText.contains("Answer from the original system prompt."))
    #expect(instructions.foundationModelsKitTestText.contains("The user is extracting reusable runtime APIs."))
    #expect(instructions.foundationModelsKitTestText.contains("Stale instructions") == false)
    #expect(entries.count == 2)
  }

  @Test("Sliding window budgets current instructions before trimming history")
  @MainActor
  func slidingWindowBudgetsCurrentInstructionsBeforeTrimmingHistory() async {
    let engine = FoundationModelConversationEngine(
      configuration: FoundationModelConversationConfiguration(
        baseInstructions: String(repeating: "system ", count: 200),
        summaryInstructions: "Summarize.",
        summaryPromptPreamble: "Summary:",
        conversationUserLabel: "User:",
        conversationAssistantLabel: "Assistant:",
        continuationNote: "Continue.",
        enableSlidingWindow: true
      )
    )
    engine.setMaxContextSize(120)

    let entries = await engine.slidingWindowEntries(
      from: Transcript(entries: [
        .prompt(.foundationModelsKitTest("Latest prompt should not fit."))
      ])
    )

    guard case .instructions(let instructions) = entries.first else {
      Issue.record("Expected budgeted entries to preserve current instructions")
      return
    }

    #expect(instructions.foundationModelsKitTestText.contains("system system"))
    #expect(entries.count == 1)
  }

  @Test("Overflow one-shot retry remains cancellable")
  @MainActor
  func overflowOneShotRetryRemainsCancellable() async {
    let engine = FoundationModelConversationEngine(
      configuration: FoundationModelConversationConfiguration(
        baseInstructions: "Answer briefly.",
        summaryInstructions: "Summarize.",
        summaryPromptPreamble: "Summary:",
        conversationUserLabel: "User:",
        conversationAssistantLabel: "Assistant:",
        continuationNote: "Continue."
      )
    )
    let retryProbe = RetryProbe()
    var responseCallCount = 0

    engine.conversationSummaryOverride = {
      FoundationModelConversationSummary(
        summary: "The user asked a question before the context overflow.",
        keyTopics: ["context recovery"],
        userPreferences: []
      )
    }
    engine.responseOverride = { _, _ in
      responseCallCount += 1
      if responseCallCount == 1 {
        throw LanguageModelSession.GenerationError.exceededContextWindowSize(
          .init(debugDescription: "Test context overflow")
        )
      }

      await retryProbe.markStarted()
      try await Task.sleep(for: .seconds(30))
      return "Late response"
    }

    let responseTask = Task { @MainActor in
      try await engine.sendMessage("Retry after recovery")
    }

    await retryProbe.waitUntilStarted()
    engine.cancelActiveResponse()

    do {
      _ = try await responseTask.value
      Issue.record("Expected overflow retry cancellation to throw")
    } catch is CancellationError {
      #expect(responseCallCount == 2)
    } catch {
      Issue.record("Expected CancellationError, received \(error)")
    }
  }
}

private actor RetryProbe {
  private var continuation: CheckedContinuation<Void, Never>?
  private var started = false

  func waitUntilStarted() async {
    if started {
      return
    }

    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func markStarted() {
    started = true
    continuation?.resume()
    continuation = nil
  }
}

private extension Transcript.Instructions {
  static func foundationModelsKitTest(_ text: String) -> Self {
    Self(
      segments: [.text(Transcript.TextSegment(content: text))],
      toolDefinitions: []
    )
  }

  var foundationModelsKitTestText: String {
    segments.foundationModelsKitTestText
  }
}

private extension Transcript.Prompt {
  static func foundationModelsKitTest(_ text: String) -> Self {
    Self(segments: [.text(Transcript.TextSegment(content: text))])
  }
}

private extension [Transcript.Segment] {
  var foundationModelsKitTestText: String {
    compactMap { segment in
      if case .text(let text) = segment {
        return text.content
      }
      return nil
    }.joined()
  }
}
