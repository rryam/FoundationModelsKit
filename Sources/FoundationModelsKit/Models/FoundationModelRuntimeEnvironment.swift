import Darwin
import Foundation

/// Observable process, build, simulator, and boot-volume facts for runtime diagnostics.
public struct FoundationModelRuntimeEnvironment: Codable, Equatable, Sendable {
    public enum ProcessKind: String, Codable, Equatable, Sendable {
        case native
        case simulator
    }

    public enum BootVolume: String, Codable, Equatable, Sendable {
        case `internal`
        case external
        case unknown
    }

    public struct BuildInformation: Codable, Equatable, Sendable {
        public let xcodeBuild: String?
        public let sdkName: String?
        public let sdkBuild: String?
        public let platformName: String?
        public let platformVersion: String?
        public let minimumOperatingSystemVersion: String?

        public init(
            xcodeBuild: String? = nil,
            sdkName: String? = nil,
            sdkBuild: String? = nil,
            platformName: String? = nil,
            platformVersion: String? = nil,
            minimumOperatingSystemVersion: String? = nil
        ) {
            self.xcodeBuild = xcodeBuild
            self.sdkName = sdkName
            self.sdkBuild = sdkBuild
            self.platformName = platformName
            self.platformVersion = platformVersion
            self.minimumOperatingSystemVersion = minimumOperatingSystemVersion
        }
    }

    public struct SimulatorInformation: Codable, Equatable, Sendable {
        public let deviceName: String?
        public let modelIdentifier: String?
        public let runtimeVersion: String?
        public let runtimeBuild: String?

        public init(
            deviceName: String? = nil,
            modelIdentifier: String? = nil,
            runtimeVersion: String? = nil,
            runtimeBuild: String? = nil
        ) {
            self.deviceName = deviceName
            self.modelIdentifier = modelIdentifier
            self.runtimeVersion = runtimeVersion
            self.runtimeBuild = runtimeBuild
        }
    }

    public let operatingSystemName: String
    public let operatingSystemVersion: String
    public let operatingSystemBuild: String?
    public let deviceModelIdentifier: String?
    public let localeIdentifier: String
    public let processKind: ProcessKind
    public let bootVolume: BootVolume
    public let build: BuildInformation
    public let simulator: SimulatorInformation?

    public init(
        operatingSystemName: String,
        operatingSystemVersion: String,
        operatingSystemBuild: String? = nil,
        deviceModelIdentifier: String? = nil,
        localeIdentifier: String,
        processKind: ProcessKind,
        bootVolume: BootVolume = .unknown,
        build: BuildInformation = BuildInformation(),
        simulator: SimulatorInformation? = nil
    ) {
        self.operatingSystemName = operatingSystemName
        self.operatingSystemVersion = operatingSystemVersion
        self.operatingSystemBuild = operatingSystemBuild
        self.deviceModelIdentifier = deviceModelIdentifier
        self.localeIdentifier = localeIdentifier
        self.processKind = processKind
        self.bootVolume = bootVolume
        self.build = build
        self.simulator = simulator
    }

    public static var current: Self {
        capture()
    }

    /// Captures values exposed to the running process. It doesn't probe model or tool assets.
    public static func capture(
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> Self {
        let processInfo = ProcessInfo.processInfo
        let version = processInfo.operatingSystemVersion
        let environment = processInfo.environment
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let build = BuildInformation(
            xcodeBuild: bundleString("DTXcodeBuild", in: bundle),
            sdkName: bundleString("DTSDKName", in: bundle),
            sdkBuild: bundleString("DTSDKBuild", in: bundle),
            platformName: bundleString("DTPlatformName", in: bundle),
            platformVersion: bundleString("DTPlatformVersion", in: bundle),
            minimumOperatingSystemVersion: bundleString("MinimumOSVersion", in: bundle)
                ?? bundleString("LSMinimumSystemVersion", in: bundle)
        )

        #if targetEnvironment(simulator)
        let processKind = ProcessKind.simulator
        let simulator = SimulatorInformation(
            deviceName: environment["SIMULATOR_DEVICE_NAME"],
            modelIdentifier: environment["SIMULATOR_MODEL_IDENTIFIER"],
            runtimeVersion: environment["SIMULATOR_RUNTIME_VERSION"],
            runtimeBuild: environment["SIMULATOR_RUNTIME_BUILD_VERSION"]
        )
        #else
        let processKind = ProcessKind.native
        let simulator: SimulatorInformation? = nil
        #endif

        return Self(
            operatingSystemName: operatingSystemName,
            operatingSystemVersion: versionString,
            operatingSystemBuild: systemString(for: "kern.osversion"),
            deviceModelIdentifier: environment["SIMULATOR_MODEL_IDENTIFIER"]
                ?? nativeModelIdentifier,
            localeIdentifier: locale.identifier,
            processKind: processKind,
            bootVolume: bootVolume,
            build: build,
            simulator: simulator
        )
    }

    private static var operatingSystemName: String {
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

    private static var nativeModelIdentifier: String? {
        #if os(macOS)
        systemString(for: "hw.model")
        #else
        systemString(for: "hw.machine")
        #endif
    }

    private static var bootVolume: BootVolume {
        #if os(macOS)
        let keys: Set<URLResourceKey> = [.volumeIsInternalKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let isInternal = values.volumeIsInternal else {
            return .unknown
        }
        return isInternal ? .internal : .external
        #else
        return .internal
        #endif
    }

    private static func bundleString(_ key: String, in bundle: Bundle) -> String? {
        bundle.infoDictionary?[key] as? String
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
        guard status == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8)
    }
}
