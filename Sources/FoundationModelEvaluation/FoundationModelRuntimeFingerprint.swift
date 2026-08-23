import Foundation
import FoundationModelsKit

public struct FoundationModelRuntimeFingerprint: Codable, Sendable, Equatable {
    public let operatingSystem: String
    public let operatingSystemBuild: String?
    public let deviceModelIdentifier: String?
    public let modelVariant: String?
    public let contextSize: Int?
    public let runtime: FoundationModelRuntime
    public let locale: String

    public init(operatingSystem: String, operatingSystemBuild: String? = nil,
                deviceModelIdentifier: String? = nil, modelVariant: String? = nil,
                contextSize: Int? = nil, runtime: FoundationModelRuntime = .onDevice,
                locale: String = Locale.current.identifier) {
        self.operatingSystem = operatingSystem
        self.operatingSystemBuild = operatingSystemBuild
        self.deviceModelIdentifier = deviceModelIdentifier
        self.modelVariant = modelVariant
        self.contextSize = contextSize
        self.runtime = runtime
        self.locale = locale
    }

    public static var current: Self {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        return Self(operatingSystem: os, deviceModelIdentifier: device)
    }
}
