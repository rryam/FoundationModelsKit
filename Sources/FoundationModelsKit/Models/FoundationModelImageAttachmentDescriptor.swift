import Foundation

/// Path-free metadata that identifies image content without retaining its pixels.
public struct FoundationModelImageAttachmentDescriptor: Codable, Hashable, Sendable {
    public let label: String
    public let orientation: FoundationModelImageAttachment.Orientation?
    public let contentTypeIdentifier: String
    public let byteCount: Int
    public let sha256Digest: String

    public init(
        label: String,
        orientation: FoundationModelImageAttachment.Orientation? = nil,
        contentTypeIdentifier: String,
        byteCount: Int,
        sha256Digest: String
    ) {
        self.label = label
        self.orientation = orientation
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = max(0, byteCount)
        self.sha256Digest = sha256Digest
    }
}
