import Darwin
import Foundation
import FoundationModels
import FoundationModelsKit

/// Public runtime and environment metadata for comparing model behavior across runs.
public struct FoundationModelRuntimeFingerprint: Codable, Equatable, Sendable {
    public let operatingSystemName: String
    public let operatingSystemVersion: String
    public let operatingSystemBuild: String?
    public let deviceModelIdentifier: String?
    public let modelVariant: String?
    public let contextSize: Int?
    public let runtime: FoundationModelRuntime
    public let localeIdentifier: String

    public init(
        operatingSystemName: String,
        operatingSystemVersion: String,
        operatingSystemBuild: String? = nil,
        deviceModelIdentifier: String? = nil,
        modelVariant: String? = nil,
        contextSize: Int? = nil,
        runtime: FoundationModelRuntime = .onDevice,
        localeIdentifier: String = Locale.current.identifier
    ) {
        self.operatingSystemName = operatingSystemName
        self.operatingSystemVersion = operatingSystemVersion
        self.operatingSystemBuild = operatingSystemBuild
        self.deviceModelIdentifier = deviceModelIdentifier
        self.modelVariant = modelVariant
        self.contextSize = contextSize
        self.runtime = runtime
        self.localeIdentifier = localeIdentifier
    }

    /// Captures the current environment and the public on-device model profile when applicable.
    public static func capture(
        runtime: FoundationModelRuntime = .onDevice,
        locale: Locale = .current,
        systemModel: SystemLanguageModel = .default
    ) -> Self {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let includesSystemModel = runtime == .onDevice
        var modelVariant: String?

        #if compiler(>=6.4)
        if includesSystemModel,
           #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *) {
            modelVariant = systemModel.variant.displayName
        }
        #endif

        return Self(
            operatingSystemName: currentOperatingSystemName,
            operatingSystemVersion: versionString,
            operatingSystemBuild: systemString(for: "kern.osversion"),
            deviceModelIdentifier: currentDeviceModelIdentifier,
            modelVariant: modelVariant,
            contextSize: includesSystemModel ? systemModel.contextSize : nil,
            runtime: runtime,
            localeIdentifier: locale.identifier
        )
    }

    public static var current: Self {
        capture()
    }

    private static var currentOperatingSystemName: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #elseif os(visionOS)
        "visionOS"
        #else
        "Apple OS"
        #endif
    }

    private static var currentDeviceModelIdentifier: String? {
        if let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulatorModel
        }

        #if os(macOS)
        return systemString(for: "hw.model")
        #else
        return systemString(for: "hw.machine")
        #endif
    }

    private static func systemString(for name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        let status = buffer.withUnsafeMutableBytes { bytes in
            sysctlbyname(name, bytes.baseAddress, &size, nil, 0)
        }
        guard status == 0 else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8)
    }
}
