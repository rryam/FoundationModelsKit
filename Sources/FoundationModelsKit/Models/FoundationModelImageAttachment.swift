import Foundation

/// A file-backed image included alongside a text-generation prompt.
///
/// File URLs are execution inputs. Evaluation recorders replace them with a
/// metadata-only representation so exported cassettes do not disclose local paths.
public struct FoundationModelImageAttachment: Codable, Hashable, Sendable {
    public enum Orientation: String, Codable, CaseIterable, Hashable, Sendable {
        case up
        case upMirrored
        case down
        case downMirrored
        case leftMirrored
        case right
        case rightMirrored
        case left
    }

    private enum StorageKind: String, Codable {
        case file
        case metadataOnly
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case orientation
        case storageKind
        case imageURL
        case descriptor
    }

    public let label: String
    public let orientation: Orientation?
    /// The local execution source. Evaluation recordings replace this with `nil`.
    public let imageURL: URL?
    /// Path-free recording metadata. Executable requests leave this as `nil`.
    public let descriptor: FoundationModelImageAttachmentDescriptor?

    public init(
        label: String,
        imageURL: URL,
        orientation: Orientation? = nil
    ) {
        self.label = label
        self.orientation = orientation
        self.imageURL = imageURL
        self.descriptor = nil
    }

    /// Creates the path-free representation used by evaluation recordings.
    public static func metadataOnly(
        _ descriptor: FoundationModelImageAttachmentDescriptor
    ) -> Self {
        Self(
            label: descriptor.label,
            orientation: descriptor.orientation,
            imageURL: nil,
            descriptor: descriptor
        )
    }

    private init(
        label: String,
        orientation: Orientation?,
        imageURL: URL?,
        descriptor: FoundationModelImageAttachmentDescriptor?
    ) {
        self.label = label
        self.orientation = orientation
        self.imageURL = imageURL
        self.descriptor = descriptor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storageKind = try container.decode(StorageKind.self, forKey: .storageKind)

        switch storageKind {
        case .file:
            self.init(
                label: try container.decode(String.self, forKey: .label),
                imageURL: try container.decode(URL.self, forKey: .imageURL),
                orientation: try container.decodeIfPresent(Orientation.self, forKey: .orientation)
            )
        case .metadataOnly:
            let descriptor = try container.decode(
                FoundationModelImageAttachmentDescriptor.self,
                forKey: .descriptor
            )
            self = .metadataOnly(descriptor)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let imageURL {
            try container.encode(StorageKind.file, forKey: .storageKind)
            try container.encode(label, forKey: .label)
            try container.encodeIfPresent(orientation, forKey: .orientation)
            try container.encode(imageURL, forKey: .imageURL)
        } else if let descriptor {
            try container.encode(StorageKind.metadataOnly, forKey: .storageKind)
            try container.encode(descriptor, forKey: .descriptor)
        } else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "An image attachment requires a file URL or metadata descriptor."
                )
            )
        }
    }
}
