import Foundation
import FoundationModels

/// Builds evaluation and Apple language-model feedback attachments without recording prompt text itself.
public struct FoundationModelFeedbackBundleBuilder: Sendable {
    public init() {}

    public func build(
        trace: FoundationModelExecutionTrace,
        appleLanguageModelFeedbackAttachment: Data? = nil
    ) -> FoundationModelFeedbackBundle {
        FoundationModelFeedbackBundle(
            trace: trace,
            appleLanguageModelFeedbackAttachment: appleLanguageModelFeedbackAttachment
        )
    }

    /// Asks the session for Apple's diagnostic attachment and pairs it with the evaluation trace.
    ///
    /// Apple's attachment may contain session content. The app remains responsible for user consent,
    /// redaction, storage, and submission.
    public func build(
        trace: FoundationModelExecutionTrace,
        session: LanguageModelSession,
        sentiment: LanguageModelFeedback.Sentiment?,
        issues: [LanguageModelFeedback.Issue] = [],
        desiredOutput: Transcript.Entry? = nil
    ) -> FoundationModelFeedbackBundle {
        let attachment = session.logFeedbackAttachment(
            sentiment: sentiment,
            issues: issues,
            desiredOutput: desiredOutput
        )
        return build(
            trace: trace,
            appleLanguageModelFeedbackAttachment: attachment
        )
    }

    /// Encodes the metadata bundle using deterministic keys for archival or CI artifacts.
    public func encodedData(
        for bundle: FoundationModelFeedbackBundle,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(bundle)
    }

    /// Produces separate files so Apple's attachment can be submitted in its native form.
    public func attachments(
        for bundle: FoundationModelFeedbackBundle
    ) throws -> [FoundationModelFeedbackAttachment] {
        var attachments = [FoundationModelFeedbackAttachment(
            suggestedFileName: "foundation-model-evaluation.json",
            data: try encodedData(for: FoundationModelFeedbackBundle(trace: bundle.trace))
        )]
        if let appleAttachment = bundle.appleLanguageModelFeedbackAttachment {
            attachments.append(FoundationModelFeedbackAttachment(
                suggestedFileName: "language-model-feedback.data",
                data: appleAttachment
            ))
        }
        return attachments
    }
}
