import Foundation
import FoundationModelsKit
import Testing

@Suite("Foundation Model image attachments")
struct FoundationModelImageAttachmentTests {
    @Test("Inspector validates an image and creates a stable path-free descriptor")
    func inspectsImage() throws {
        let expectedPNGData = try pngData()
        let firstURL = try temporaryPNG(named: "first.png")
        let secondURL = try temporaryPNG(named: "second.png")
        defer {
            removeTemporaryItem(containing: firstURL)
            removeTemporaryItem(containing: secondURL)
        }
        let inspector = FoundationModelImageAttachmentInspector()

        let first = try inspector.descriptors(for: [
            FoundationModelImageAttachment(
                label: "source-image",
                imageURL: firstURL,
                orientation: .right
            )
        ]).first
        let second = try inspector.descriptors(for: [
            FoundationModelImageAttachment(
                label: "source-image",
                imageURL: secondURL,
                orientation: .right
            )
        ]).first

        #expect(first?.label == "source-image")
        #expect(first?.orientation == .right)
        #expect(first?.contentTypeIdentifier.localizedStandardContains("png") == true)
        #expect(first?.byteCount == expectedPNGData.count)
        #expect(first?.sha256Digest.count == 64)
        #expect(first == second)
    }

    @Test("Inspector rejects duplicate labels, non-images, and oversized inputs")
    func rejectsUnsafeInputs() throws {
        let expectedPNGData = try pngData()
        let imageURL = try temporaryPNG(named: "valid.png")
        let textURL = try temporaryFile(named: "not-image.txt", data: Data("hello".utf8))
        defer {
            removeTemporaryItem(containing: imageURL)
            removeTemporaryItem(containing: textURL)
        }
        let duplicate = FoundationModelImageAttachment(label: "same", imageURL: imageURL)

        #expect(throws: FoundationModelsKitError.self) {
            _ = try FoundationModelImageAttachmentInspector().descriptors(
                for: [duplicate, duplicate]
            )
        }
        #expect(throws: FoundationModelsKitError.self) {
            _ = try FoundationModelImageAttachmentInspector().descriptors(for: [
                FoundationModelImageAttachment(label: "text", imageURL: textURL)
            ])
        }
        #expect(throws: FoundationModelsKitError.self) {
            _ = try FoundationModelImageAttachmentInspector(
                policy: FoundationModelImageAttachmentPolicy(
                    maximumBytesPerAttachment: expectedPNGData.count - 1
                )
            ).descriptors(for: [
                FoundationModelImageAttachment(label: "large", imageURL: imageURL)
            ])
        }
    }

    @Test("Metadata-only attachments encode without a file URL")
    func metadataOnlyEncodingOmitsPath() throws {
        let descriptor = FoundationModelImageAttachmentDescriptor(
            label: "private-photo",
            contentTypeIdentifier: "public.png",
            byteCount: 42,
            sha256Digest: String(repeating: "a", count: 64)
        )
        let attachment = FoundationModelImageAttachment.metadataOnly(descriptor)

        let data = try JSONEncoder().encode(attachment)
        let json = try #require(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(
            FoundationModelImageAttachment.self,
            from: data
        )

        #expect(!json.contains("imageURL"))
        #expect(decoded == attachment)
        #expect(decoded.imageURL == nil)
        #expect(decoded.descriptor == descriptor)
    }

    @Test("Requests without imageAttachments retain their legacy Codable shape")
    func requestCodableDefaultsToNoAttachments() throws {
        let request = FoundationModelTextGenerationRequest(
            prompt: "Prompt",
            context: FoundationModelInvocationContext(source: .app)
        )

        let data = try JSONEncoder().encode(request)
        let json = try #require(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(
            FoundationModelTextGenerationRequest.self,
            from: data
        )

        #expect(!json.contains("imageAttachments"))
        #expect(decoded == request)
        #expect(decoded.imageAttachments.isEmpty)
    }
}

private let pngBase64 = """
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=
"""

private func pngData() throws -> Data {
    try #require(Data(base64Encoded: pngBase64))
}

private func temporaryPNG(named name: String) throws -> URL {
    try temporaryFile(named: name, data: pngData())
}

private func temporaryFile(named name: String, data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "FoundationModelsKitTests-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let url = directory.appending(path: name)
    try data.write(to: url, options: .atomic)
    return url
}

private func removeTemporaryItem(containing url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}
