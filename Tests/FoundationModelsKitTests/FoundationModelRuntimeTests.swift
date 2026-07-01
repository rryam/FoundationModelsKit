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
  }
}
