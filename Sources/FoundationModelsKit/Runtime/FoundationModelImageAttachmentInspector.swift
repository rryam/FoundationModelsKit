import CryptoKit
import Foundation
import ImageIO

/// Validates image inputs and creates path-free descriptors for recording and replay.
public struct FoundationModelImageAttachmentInspector: Sendable {
    private struct FileMetadata {
        let contentTypeIdentifier: String
        let byteCount: Int
    }

    public let policy: FoundationModelImageAttachmentPolicy

    public init(policy: FoundationModelImageAttachmentPolicy = .default) {
        self.policy = policy
    }

    public func descriptors(
        for attachments: [FoundationModelImageAttachment]
    ) throws -> [FoundationModelImageAttachmentDescriptor] {
        try validateCollection(attachments)
        return try attachments.map(descriptor)
    }

    /// Validates executable files without calculating recording fingerprints.
    public func validateForExecution(
        _ attachments: [FoundationModelImageAttachment]
    ) throws {
        try validateCollection(attachments)
        for attachment in attachments {
            guard attachment.imageURL != nil, attachment.descriptor == nil else {
                throw FoundationModelsKitError.invalidRequest(
                    "Metadata-only image attachment '\(attachment.label)' cannot be executed"
                )
            }
            _ = try fileMetadata(for: attachment)
        }
    }

    private func validateCollection(
        _ attachments: [FoundationModelImageAttachment]
    ) throws {
        guard attachments.count <= policy.maximumAttachmentCount else {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment count exceeds the configured maximum of \(policy.maximumAttachmentCount)"
            )
        }

        try validateLabels(attachments.map(\.label))
    }

    private func descriptor(
        for attachment: FoundationModelImageAttachment
    ) throws -> FoundationModelImageAttachmentDescriptor {
        if let descriptor = attachment.descriptor {
            try validate(descriptor, for: attachment)
            return descriptor
        }

        guard let imageURL = attachment.imageURL else {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment '\(attachment.label)' has no executable file URL"
            )
        }
        let metadata = try fileMetadata(for: attachment)

        return FoundationModelImageAttachmentDescriptor(
            label: attachment.label,
            orientation: attachment.orientation,
            contentTypeIdentifier: metadata.contentTypeIdentifier,
            byteCount: metadata.byteCount,
            sha256Digest: try sha256Digest(of: imageURL, label: attachment.label)
        )
    }

    private func fileMetadata(
        for attachment: FoundationModelImageAttachment
    ) throws -> FileMetadata {
        guard let imageURL = attachment.imageURL, imageURL.isFileURL else {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment '\(attachment.label)' must use a local file URL"
            )
        }

        let values: URLResourceValues
        do {
            values = try imageURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment '\(attachment.label)' cannot be inspected"
            )
        }

        guard values.isRegularFile == true, let byteCount = values.fileSize, byteCount > 0 else {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment '\(attachment.label)' must reference a nonempty regular file"
            )
        }
        guard byteCount <= policy.maximumBytesPerAttachment else {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment '\(attachment.label)' exceeds the configured byte limit"
            )
        }
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let contentType = CGImageSourceGetType(imageSource) as String? else {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment '\(attachment.label)' is not a supported image file"
            )
        }

        return FileMetadata(
            contentTypeIdentifier: contentType,
            byteCount: byteCount
        )
    }

    private func validate(
        _ descriptor: FoundationModelImageAttachmentDescriptor,
        for attachment: FoundationModelImageAttachment
    ) throws {
        let digestCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard descriptor.label == attachment.label,
              descriptor.orientation == attachment.orientation,
              !descriptor.contentTypeIdentifier.isEmpty,
              descriptor.byteCount > 0,
              descriptor.byteCount <= policy.maximumBytesPerAttachment,
              descriptor.sha256Digest.count == 64,
              descriptor.sha256Digest.unicodeScalars.allSatisfy(digestCharacters.contains) else {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment '\(attachment.label)' has invalid recorded metadata"
            )
        }
    }

    private func validateLabels(_ labels: [String]) throws {
        var uniqueLabels: Set<String> = []
        for label in labels {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed == label,
                  !label.unicodeScalars.contains(
                    where: CharacterSet.controlCharacters.contains
                  ) else {
                throw FoundationModelsKitError.invalidRequest(
                    "Image attachment labels must be nonempty and contain no surrounding " +
                    "whitespace or control characters"
                )
            }
            guard uniqueLabels.insert(label).inserted else {
                throw FoundationModelsKitError.invalidRequest(
                    "Image attachment labels must be unique"
                )
            }
        }
    }

    private func sha256Digest(of url: URL, label: String) throws -> String {
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: url)
        } catch {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment '\(label)' cannot be read"
            )
        }
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        do {
            while let chunk = try fileHandle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            throw FoundationModelsKitError.invalidRequest(
                "Image attachment '\(label)' could not be fingerprinted"
            )
        }

        return hasher.finalize().map(Self.hexByte).joined()
    }

    private static func hexByte(_ byte: UInt8) -> String {
        let value = String(byte, radix: 16)
        return value.count == 1 ? "0\(value)" : value
    }
}
