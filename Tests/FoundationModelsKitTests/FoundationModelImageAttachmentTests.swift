import Foundation
import FoundationModels
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

    @Test("File-backed attachments round-trip through Codable")
    func fileBackedCodableRoundTrip() throws {
        let attachment = FoundationModelImageAttachment(
            label: "receipt",
            imageURL: URL(filePath: "/tmp/receipt.png"),
            orientation: .right
        )

        let decoded = try JSONDecoder().decode(
            FoundationModelImageAttachment.self,
            from: JSONEncoder().encode(attachment)
        )

        #expect(decoded == attachment)
    }

    @Test("A zero attachment budget rejects every image")
    func zeroAttachmentBudgetRejectsImages() throws {
        let imageURL = try temporaryPNG(named: "valid.png")
        defer { removeTemporaryItem(containing: imageURL) }
        let inspector = FoundationModelImageAttachmentInspector(
            policy: FoundationModelImageAttachmentPolicy(maximumAttachmentCount: 0)
        )

        #expect(throws: FoundationModelsKitError.invalidRequest(
            "Image attachment count exceeds the configured maximum of 0"
        )) {
            try inspector.validateForExecution([
                FoundationModelImageAttachment(label: "image", imageURL: imageURL)
            ])
        }
        #expect(try inspector.descriptors(for: []).isEmpty)
    }

    @Test("Inspector re-reads a file rewritten at the same URL")
    func reinspectsRewrittenFile() throws {
        let original = try pngData()
        let imageURL = try temporaryPNG(named: "capture.png")
        defer { removeTemporaryItem(containing: imageURL) }
        let attachment = FoundationModelImageAttachment(label: "capture", imageURL: imageURL)
        let inspector = FoundationModelImageAttachmentInspector(
            policy: FoundationModelImageAttachmentPolicy(
                maximumBytesPerAttachment: original.count * 2
            )
        )
        let first = try #require(try inspector.descriptors(for: [attachment]).first)

        var larger = original
        larger.append(Data(repeating: 0, count: original.count))
        try larger.write(to: imageURL, options: .atomic)
        let second = try #require(try inspector.descriptors(for: [attachment]).first)

        #expect(first.byteCount == original.count)
        #expect(second.byteCount == larger.count)

        larger.append(0)
        try larger.write(to: imageURL, options: .atomic)
        #expect(throws: FoundationModelsKitError.invalidRequest(
            "Image attachment 'capture' exceeds the configured byte limit"
        )) {
            try inspector.validateForExecution([attachment])
        }
    }

    @Test("Inspector follows symbolic links to image files")
    func followsSymbolicLinks() throws {
        let imageURL = try temporaryPNG(named: "target.png")
        defer { removeTemporaryItem(containing: imageURL) }
        let directory = imageURL.deletingLastPathComponent()
        let linkURL = directory.appending(path: "link.png")
        let danglingURL = directory.appending(path: "dangling.png")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: imageURL)
        try FileManager.default.createSymbolicLink(
            at: danglingURL,
            withDestinationURL: directory.appending(path: "missing.png")
        )
        let inspector = FoundationModelImageAttachmentInspector()

        let linked = try inspector.descriptors(for: [
            FoundationModelImageAttachment(label: "image", imageURL: linkURL)
        ])
        let direct = try inspector.descriptors(for: [
            FoundationModelImageAttachment(label: "image", imageURL: imageURL)
        ])

        #expect(linked == direct)
        #expect(throws: FoundationModelsKitError.self) {
            try inspector.validateForExecution([
                FoundationModelImageAttachment(label: "image", imageURL: danglingURL)
            ])
        }
    }

    @Test("Generator rejects invalid image attachments before creating a model session")
    func generatorRejectsInvalidAttachments() async throws {
        #if compiler(>=6.4)
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *) else {
            return
        }
        let imageURL = try temporaryPNG(named: "valid.png")
        defer { removeTemporaryItem(containing: imageURL) }
        let metadataOnly = FoundationModelImageAttachment.metadataOnly(
            FoundationModelImageAttachmentDescriptor(
                label: "recorded",
                contentTypeIdentifier: "public.png",
                byteCount: 10,
                sha256Digest: String(repeating: "a", count: 64)
            )
        )
        let remoteURL = try #require(URL(string: "https://example.com/a.png"))
        let cases: [([FoundationModelImageAttachment], String)] = [
            (
                [metadataOnly],
                "Metadata-only image attachment 'recorded' cannot be executed"
            ),
            (
                [FoundationModelImageAttachment(label: "remote", imageURL: remoteURL)],
                "Image attachment 'remote' must use a local file URL"
            ),
            (
                [FoundationModelImageAttachment(label: " padded ", imageURL: imageURL)],
                "Image attachment labels must be nonempty and contain no surrounding " +
                    "whitespace or control characters"
            ),
            (
                (0..<9).map {
                    FoundationModelImageAttachment(label: "image-\($0)", imageURL: imageURL)
                },
                "Image attachment count exceeds the configured maximum of 8"
            )
        ]

        for (attachments, message) in cases {
            await #expect(throws: FoundationModelsKitError.invalidRequest(message)) {
                _ = try await FoundationModelsTextGenerator().generateText(
                    for: FoundationModelTextGenerationRequest(
                        prompt: "Describe the image.",
                        imageAttachments: attachments,
                        context: FoundationModelInvocationContext(source: .app)
                    )
                )
            }
        }
        #endif
    }

    @Test(
        "Image requests report the model's observed token usage",
        .enabled(if: SystemLanguageModel.default.isAvailable)
    )
    func imageRequestsReportObservedTokenUsage() async throws {
        #if compiler(>=6.4)
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *) else {
            return
        }
        let imageURL = try temporaryPNG(named: "photo.png")
        defer { removeTemporaryItem(containing: imageURL) }

        let result = try await FoundationModelsTextGenerator().generateText(
            for: FoundationModelTextGenerationRequest(
                prompt: "Describe the attached image in one word.",
                imageAttachments: [
                    FoundationModelImageAttachment(label: "photo", imageURL: imageURL)
                ],
                context: FoundationModelInvocationContext(source: .app)
            )
        )

        // The character estimate reports about 25 tokens here; the model reports about 90.
        let tokenCount = try #require(result.metadata.tokenCount)
        #expect(tokenCount > 50)
        #endif
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
