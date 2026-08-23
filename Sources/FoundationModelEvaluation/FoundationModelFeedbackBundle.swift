import Foundation

/// Evaluation metadata plus the optional framework-produced language-model feedback attachment.
public struct FoundationModelFeedbackBundle: Codable, Equatable, Sendable {
    public let trace: FoundationModelExecutionTrace
    public let appleLanguageModelFeedbackAttachment: Data?

    public init(
        trace: FoundationModelExecutionTrace,
        appleLanguageModelFeedbackAttachment: Data? = nil
    ) {
        self.trace = trace
        self.appleLanguageModelFeedbackAttachment = appleLanguageModelFeedbackAttachment
    }
}

/// One file ready to add to Feedback Assistant.
public struct FoundationModelFeedbackAttachment: Equatable, Sendable {
    public let suggestedFileName: String
    public let data: Data

    public init(suggestedFileName: String, data: Data) {
        self.suggestedFileName = suggestedFileName
        self.data = data
    }
}
