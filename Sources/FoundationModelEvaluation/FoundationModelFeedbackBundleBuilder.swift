import Foundation

public struct FoundationModelFeedbackBundle: Codable, Sendable, Equatable {
    public let trace: FoundationModelExecutionTrace
    public let appleLanguageModelFeedbackAttachment: Data?
    public init(trace: FoundationModelExecutionTrace, appleLanguageModelFeedbackAttachment: Data? = nil) {
        self.trace = trace
        self.appleLanguageModelFeedbackAttachment = appleLanguageModelFeedbackAttachment
    }
}

public struct FoundationModelFeedbackBundleBuilder: Sendable {
    public init() {}
    public func build(trace: FoundationModelExecutionTrace, appleLanguageModelFeedbackAttachment: Data? = nil) throws -> Data {
        try JSONEncoder().encode(FoundationModelFeedbackBundle(trace: trace,
            appleLanguageModelFeedbackAttachment: appleLanguageModelFeedbackAttachment))
    }
}
