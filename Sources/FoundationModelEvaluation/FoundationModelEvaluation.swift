import Foundation

/// A privacy-safe snapshot of the environment in which an evaluation ran.
public struct FoundationModelRuntimeFingerprint: Codable, Sendable, Equatable {
    public let operatingSystem: String
    public let build: String
    public let device: String
    public let modelVariant: String?
    public let contextSize: Int?
    public let runtime: String
    public let locale: String

    public init(operatingSystem: String, build: String, device: String,
                modelVariant: String? = nil, contextSize: Int? = nil,
                runtime: String = "Foundation Models", locale: String = Locale.current.identifier) {
        self.operatingSystem = operatingSystem; self.build = build; self.device = device
        self.modelVariant = modelVariant; self.contextSize = contextSize
        self.runtime = runtime; self.locale = locale
    }

    public static var current: Self {
        let process = ProcessInfo.processInfo
        return Self(operatingSystem: process.operatingSystemVersionString,
                    build: process.operatingSystemVersionString,
                    device: process.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Unknown",
                    locale: Locale.current.identifier)
    }
}

public struct FoundationModelExecutionTrace: Codable, Sendable, Equatable {
    public let fingerprint: FoundationModelRuntimeFingerprint
    public let toolCallSequence: [String]
    public let repairCount: Int
    public let latencyMilliseconds: Int?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let schemaValid: Bool?
    public let refusalCategory: String?
    public let errorCategory: String?
    public let succeeded: Bool

    public init(fingerprint: FoundationModelRuntimeFingerprint,
                toolCallSequence: [String] = [], repairCount: Int = 0,
                latencyMilliseconds: Int? = nil, inputTokens: Int? = nil,
                outputTokens: Int? = nil, schemaValid: Bool? = nil,
                refusalCategory: String? = nil, errorCategory: String? = nil,
                succeeded: Bool) {
        self.fingerprint = fingerprint; self.toolCallSequence = toolCallSequence
        self.repairCount = repairCount; self.latencyMilliseconds = latencyMilliseconds
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.schemaValid = schemaValid; self.refusalCategory = refusalCategory
        self.errorCategory = errorCategory; self.succeeded = succeeded
    }
}

public struct FoundationModelEvaluationRequest: Sendable {
    public let fingerprint: FoundationModelRuntimeFingerprint
    public init(fingerprint: FoundationModelRuntimeFingerprint = .current) { self.fingerprint = fingerprint }
}

public struct FoundationModelEvaluationResult: Sendable {
    public let trace: FoundationModelExecutionTrace
    public init(trace: FoundationModelExecutionTrace) { self.trace = trace }
}

public struct FoundationModelEvaluationRunner: Sendable {
    public typealias Executor = @Sendable (FoundationModelEvaluationRequest) async throws -> FoundationModelExecutionTrace
    private let executor: Executor

    public init(executor: @escaping Executor) { self.executor = executor }

    public func run(_ request: FoundationModelEvaluationRequest = .init()) async -> FoundationModelEvaluationResult {
        do { return FoundationModelEvaluationResult(trace: try await executor(request)) } catch {
            return FoundationModelEvaluationResult(trace: FoundationModelExecutionTrace(
                fingerprint: request.fingerprint, errorCategory: String(describing: type(of: error)), succeeded: false))
        }
    }
}

/// Builds an exportable metadata bundle. Prompt and response content are never included.
public struct FoundationModelFeedbackBundleBuilder: Sendable {
    public init() {}
    public func build(from trace: FoundationModelExecutionTrace) throws -> Data {
        try JSONEncoder().encode(trace)
    }

    #if canImport(FoundationModels)
    /// Hook for attaching this metadata to Apple's public feedback APIs when available.
    @available(macOS 26, iOS 26, *)
    public func attachmentData(from trace: FoundationModelExecutionTrace) throws -> Data { try build(from: trace) }
    #endif
}
