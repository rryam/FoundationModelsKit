import FoundationModels
import Testing
@testable import FoundationModelsKit

@Suite("Transcript Text Content Tests")
struct TranscriptTextContentTests {
    @Test("Text segments join with spaces")
    func textSegmentsJoinWithSpaces() {
        let segments: [Transcript.Segment] = [
            .text(.init(content: "Hello")),
            .text(.init(content: "Foundation Models"))
        ]

        #expect(segments.joinedTextContent() == "Hello Foundation Models")
    }

    @Test("Segments without text return nil")
    func segmentsWithoutTextReturnNil() {
        let segments: [Transcript.Segment] = []

        #expect(segments.joinedTextContent() == nil)
    }

    @Test("Transcript entry extracts prompt, response, and tool output text")
    func entryExtractsTextContent() {
        let prompt = Transcript.Entry.prompt(
            .init(segments: [.text(.init(content: "Question"))])
        )
        let response = Transcript.Entry.response(
            .init(assetIDs: [], segments: [.text(.init(content: "Answer"))])
        )
        let toolOutput = Transcript.Entry.toolOutput(
            .foundationModelsKitTextContent(id: "weather-1", text: "Sunny")
        )

        #expect(prompt.textContentJoined() == "Question")
        #expect(response.textContentJoined() == "Answer")
        #expect(toolOutput.textContentJoined() == "Sunny")
    }

    @Test("Latest response after an index ignores earlier responses")
    func latestResponseAfterIndexIgnoresEarlierResponses() {
        let staleResponse = Transcript.Entry.response(
            .init(assetIDs: [], segments: [.text(.init(content: "Old answer"))])
        )
        let currentResponse = Transcript.Entry.response(
            .init(assetIDs: [], segments: [.text(.init(content: "Current answer"))])
        )
        let transcript = Transcript(entries: [staleResponse, currentResponse])

        #expect(transcript.latestResponseText(after: 1) == "Current answer")
        #expect(transcript.latestNonEmptyResponseText(startingAt: 1) == "Current answer")
        #expect(Transcript(entries: [staleResponse]).latestNonEmptyResponseText(startingAt: 1) == nil)
    }
}

private extension Transcript.ToolOutput {
    static func foundationModelsKitTextContent(id: String, text: String) -> Self {
        Self(
            id: id,
            toolName: "testTool",
            segments: [.text(Transcript.TextSegment(content: text))]
        )
    }
}
