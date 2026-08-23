import Foundation

/// Builds a structured Foundation Models preflight report from public runtime and process facts.
public struct FoundationModelEnvironmentDiagnostics: Sendable {
    private let inspector: any FoundationModelRuntimeInspecting
    private let environment: FoundationModelRuntimeEnvironment

    public init(
        inspector: any FoundationModelRuntimeInspecting = FoundationModelsRuntimeInspector(),
        environment: FoundationModelRuntimeEnvironment = .current
    ) {
        self.inspector = inspector
        self.environment = environment
    }

    public func report(
        for runtime: FoundationModelRuntime,
        capturedAt: Date = Date()
    ) -> FoundationModelEnvironmentReport {
        let status = inspector.status(for: runtime)
        return FoundationModelEnvironmentReport(
            capturedAt: capturedAt,
            environment: environment,
            runtimeStatus: status,
            issues: environmentIssues(for: status),
            limitations: limitations()
        )
    }

    private func environmentIssues(
        for status: FoundationModelRuntimeStatus
    ) -> [FoundationModelEnvironmentIssue] {
        var issues: [FoundationModelEnvironmentIssue] = []

        if environment.bootVolume == .external, environment.operatingSystemName == "macOS" {
            issues.append(issue(
                .externalBootVolume,
                actions: [.bootFromInternalVolume]
            ))
        }

        if let minimumVersion = environment.build.minimumOperatingSystemVersion,
           Self.version(minimumVersion, isBelow: (26, 0)) {
            issues.append(issue(
                .deploymentTargetBelowRequired,
                actions: [.useSupportedOperatingSystem]
            ))
        }

        if environment.processKind == .simulator,
           let sdkVersion = environment.build.platformVersion,
           let runtimeVersion = environment.simulator?.runtimeVersion,
           !Self.versionsMatch(sdkVersion, runtimeVersion) {
            issues.append(issue(
                .sdkRuntimeVersionMismatch,
                actions: [.alignXcodeSDKSimulatorAndHost]
            ))
        }

        if let statusIssue = runtimeIssue(for: status) {
            issues.append(statusIssue)
        }
        return issues
    }

    private func runtimeIssue(
        for status: FoundationModelRuntimeStatus
    ) -> FoundationModelEnvironmentIssue? {
        guard !status.isRunnableInCurrentProcess else { return nil }

        switch status.reason {
        case .unsupportedOperatingSystem:
            return issue(.unsupportedOperatingSystem, actions: [.useSupportedOperatingSystem])
        case .unsupportedToolchain:
            return issue(.unsupportedToolchain, actions: [.useSupportedToolchain])
        case .deviceNotEligible:
            return issue(.deviceNotEligible, actions: [.useEligibleDevice])
        case .appleIntelligenceNotEnabled:
            return issue(.appleIntelligenceNotEnabled, actions: [.enableAppleIntelligence])
        case .modelNotReady:
            return issue(
                .modelNotReady,
                severity: .warning,
                actions: [
                    .waitForModelAssets,
                    .alignXcodeSDKSimulatorAndHost,
                    .collectSysdiagnoseAndFileFeedback
                ]
            )
        case .systemNotReady:
            return issue(
                .systemNotReady,
                severity: .warning,
                actions: [
                    .waitForModelAssets,
                    .alignXcodeSDKSimulatorAndHost,
                    .collectSysdiagnoseAndFileFeedback
                ]
            )
        case .missingEntitlement:
            return issue(
                .missingPrivateCloudEntitlement,
                actions: [.addPrivateCloudComputeEntitlement]
            )
        case .unknown, .none:
            return issue(
                .unknownRuntimeState,
                severity: .warning,
                actions: [.inspectRuntimeStatus, .collectSysdiagnoseAndFileFeedback]
            )
        }
    }

    private func limitations() -> [FoundationModelEnvironmentReport.Limitation] {
        var values: [FoundationModelEnvironmentReport.Limitation] = [
            .toolSpecificAssetReadinessNotExposed
        ]
        if environment.processKind == .simulator {
            values.append(.simulatorHostOperatingSystemNotExposed)
        }
        if environment.operatingSystemName == "macOS" {
            values.append(.virtualizationStateNotExposed)
        }
        return values
    }

    private func issue(
        _ code: FoundationModelEnvironmentIssue.Code,
        severity: FoundationModelEnvironmentIssue.Severity = .error,
        actions: [FoundationModelEnvironmentIssue.Action]
    ) -> FoundationModelEnvironmentIssue {
        FoundationModelEnvironmentIssue(
            code: code,
            severity: severity,
            actions: actions
        )
    }

    private static func versionsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        guard left.count >= 2, right.count >= 2 else { return true }
        return left.prefix(2).elementsEqual(right.prefix(2))
    }

    private static func version(_ value: String, isBelow minimum: (Int, Int)) -> Bool {
        let components = versionComponents(value)
        guard let major = components.first else { return false }
        let minor = components.count > 1 ? components[1] : 0
        return (major, minor) < minimum
    }

    private static func versionComponents(_ value: String) -> [Int] {
        value.split(separator: ".").compactMap { component in
            Int(component.prefix { $0.isNumber })
        }
    }
}
