import Foundation

/// Local safety budgets applied before image content reaches a model session.
///
/// These are package defaults rather than documented model limits. Apps can tune
/// them for their own memory budget and accepted workflows.
public struct FoundationModelImageAttachmentPolicy: Hashable, Sendable {
    public static let `default` = Self()

    public let maximumAttachmentCount: Int
    public let maximumBytesPerAttachment: Int

    public init(
        maximumAttachmentCount: Int = 8,
        maximumBytesPerAttachment: Int = 20 * 1_024 * 1_024
    ) {
        self.maximumAttachmentCount = max(1, maximumAttachmentCount)
        self.maximumBytesPerAttachment = max(1, maximumBytesPerAttachment)
    }
}
