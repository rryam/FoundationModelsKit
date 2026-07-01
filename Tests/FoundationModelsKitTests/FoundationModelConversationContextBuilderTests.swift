import FoundationModels
import Testing
@testable import FoundationModelsKit

@Suite("Foundation Model Conversation Context Builder Tests")
struct FoundationModelConversationContextBuilderTests {
  @Test("Conversation text includes tool calls and outputs")
  func conversationTextIncludesToolCallsAndOutputs() {
    let transcript = Transcript(entries: [
      .prompt(.foundationModelsKitTest("What is the weather?")),
      .toolCalls(Transcript.ToolCalls(id: "weather-call", [])),
      .toolOutput(
        Transcript.ToolOutput(
          id: "weather-output",
          toolName: "weather",
          segments: [.text(Transcript.TextSegment(content: "Sunny and 72 degrees"))]
        )
      ),
      .response(.init(assetIDs: [], segments: [.text(.init(content: "It is sunny."))]))
    ])

    let text = FoundationModelConversationContextBuilder.conversationText(
      from: transcript,
      userLabel: "User:",
      assistantLabel: "Assistant:"
    )

    #expect(text.contains("User: What is the weather?"))
    #expect(text.contains("Tool Call: weather-call"))
    #expect(text.contains("Tool Output (weather): Sunny and 72 degrees"))
    #expect(text.contains("Assistant: It is sunny."))
  }
}

private extension Transcript.Prompt {
  static func foundationModelsKitTest(_ text: String) -> Self {
    Self(segments: [.text(Transcript.TextSegment(content: text))])
  }
}
