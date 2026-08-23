import Foundation
import Testing
@testable import FoundationModelsKit

@Suite("Foundation Model environment diagnostics")
struct EnvironmentDiagnosticsTests {
    @Test("A runnable native environment permits an authoritative request attempt")
    func runnableEnvironment() {
        let report = diagnostics(
            status: FoundationModelRuntimeStatus(runtime: .onDevice, isAvailable: true)
        ).report(
            for: .onDevice,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(report.canAttemptRequest)
        #expect(report.issues.isEmpty)
        #expect(report.limitations.contains(.toolSpecificAssetReadinessNotExposed))
    }

    @Test("Runtime reasons map to typed actions")
    func mapsRuntimeReason() throws {
        let report = diagnostics(
            status: FoundationModelRuntimeStatus(
                runtime: .onDevice,
                isAvailable: false,
                reason: .appleIntelligenceNotEnabled
            )
        ).report(for: .onDevice)
        let issue = try #require(report.issues.last)

        #expect(!report.canAttemptRequest)
        #expect(issue.code == .appleIntelligenceNotEnabled)
        #expect(issue.actions == [.enableAppleIntelligence])
    }

    @Test("PCC reports a missing managed entitlement")
    func reportsMissingEntitlement() throws {
        let report = diagnostics(
            status: FoundationModelRuntimeStatus(
                runtime: .privateCloudCompute,
                isAvailable: true,
                authorization: .missing
            )
        ).report(for: .privateCloudCompute)
        let issue = try #require(report.issues.last)

        #expect(issue.code == .missingPrivateCloudEntitlement)
        #expect(issue.actions == [.addPrivateCloudComputeEntitlement])
    }

    @Test("External macOS boot volumes remain visible even when availability says available")
    func reportsExternalBootVolume() {
        let environment = FoundationModelRuntimeEnvironment(
            operatingSystemName: "macOS",
            operatingSystemVersion: "26.6",
            localeIdentifier: "en_US",
            processKind: .native,
            bootVolume: .external
        )
        let report = FoundationModelEnvironmentDiagnostics(
            inspector: StubRuntimeInspector(
                status: FoundationModelRuntimeStatus(runtime: .onDevice, isAvailable: true)
            ),
            environment: environment
        ).report(for: .onDevice)

        #expect(!report.canAttemptRequest)
        #expect(report.issues.map(\.code) == [.externalBootVolume])
        #expect(report.limitations.contains(.virtualizationStateNotExposed))
    }

    @Test("Simulator SDK and runtime versions must match through minor version")
    func reportsSimulatorVersionMismatch() {
        let environment = FoundationModelRuntimeEnvironment(
            operatingSystemName: "iOS",
            operatingSystemVersion: "26.1",
            localeIdentifier: "en_US",
            processKind: .simulator,
            build: .init(platformVersion: "26.2"),
            simulator: .init(runtimeVersion: "26.1")
        )
        let report = FoundationModelEnvironmentDiagnostics(
            inspector: StubRuntimeInspector(
                status: FoundationModelRuntimeStatus(runtime: .onDevice, isAvailable: true)
            ),
            environment: environment
        ).report(for: .onDevice)

        #expect(report.issues.map(\.code) == [.sdkRuntimeVersionMismatch])
        #expect(report.limitations.contains(.simulatorHostOperatingSystemNotExposed))
    }

    @Test("Reports round-trip observable facts and limitations")
    func reportRoundTrips() throws {
        let report = diagnostics(
            status: FoundationModelRuntimeStatus(
                runtime: .onDevice,
                isAvailable: false,
                reason: .modelNotReady
            )
        ).report(
            for: .onDevice,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(
            FoundationModelEnvironmentReport.self,
            from: data
        )

        #expect(decoded == report)
        #expect(decoded.issues.first?.severity == .warning)
    }

    private func diagnostics(
        status: FoundationModelRuntimeStatus
    ) -> FoundationModelEnvironmentDiagnostics {
        FoundationModelEnvironmentDiagnostics(
            inspector: StubRuntimeInspector(status: status),
            environment: FoundationModelRuntimeEnvironment(
                operatingSystemName: "iOS",
                operatingSystemVersion: "26.6",
                localeIdentifier: "en_US",
                processKind: .native,
                bootVolume: .internal,
                build: .init(minimumOperatingSystemVersion: "26.0")
            )
        )
    }
}

private struct StubRuntimeInspector: FoundationModelRuntimeInspecting {
    let status: FoundationModelRuntimeStatus

    func status(for runtime: FoundationModelRuntime) -> FoundationModelRuntimeStatus {
        _ = runtime
        return status
    }

    func quotaUsage(for runtime: FoundationModelRuntime) -> FoundationModelQuotaUsage {
        FoundationModelQuotaUsage(runtime: runtime, status: .notApplicable)
    }
}
