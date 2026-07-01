import Foundation
import Testing
@testable import FoundationModelsKit

@Test("Runtime inspection preserves requested ordering")
func runtimeInspectionPreservesOrdering() {
    let useCase = FoundationModelRuntimeInspectionUseCase(inspector: StubRuntimeInspector())

    let results = useCase.execute(runtimes: [.privateCloudCompute, .onDevice])

    #expect(results.map(\.runtime) == [.privateCloudCompute, .onDevice])
    #expect(results.map(\.isRunnableInCurrentProcess) == [false, true])
}

@Test("Quota inspection reports system quota as not applicable")
func quotaInspectionReportsSystemAsNotApplicable() {
    let useCase = FoundationModelQuotaUsageInspectionUseCase(inspector: StubRuntimeInspector())

    let results = useCase.execute(runtimes: [.onDevice, .privateCloudCompute])

    #expect(results.map(\.status) == [.notApplicable, .approachingLimit])
}

@Test(
    "Unconfirmed managed entitlement makes PCC non-runnable",
    arguments: [
        (FoundationModelRuntimeAuthorization.missing, FoundationModelRuntimeUnavailableReason.missingEntitlement),
        (.unknown, .unknown),
        (.notRequired, .unknown)
    ]
)
func unconfirmedEntitlementMakesPCCNonRunnable(
    authorization: FoundationModelRuntimeAuthorization,
    expectedReason: FoundationModelRuntimeUnavailableReason
) {
    let result = FoundationModelRuntimeStatus(
        runtime: .privateCloudCompute,
        isAvailable: true,
        authorization: authorization
    )

    #expect(result.isSupported)
    #expect(!result.isRunnableInCurrentProcess)
    #expect(result.authorization == authorization)
    #expect(result.reason == expectedReason)
}

@Test(
    "Skipped PCC quota preserves the authorization failure reason",
    arguments: [
        (FoundationModelRuntimeAuthorization.missing, FoundationModelRuntimeUnavailableReason.missingEntitlement),
        (.unknown, .unknown)
    ]
)
func skippedPCCQuotaPreservesAuthorizationReason(
    authorization: FoundationModelRuntimeAuthorization,
    expectedReason: FoundationModelRuntimeUnavailableReason
) throws {
    let runtimeStatus = FoundationModelRuntimeStatus(
        runtime: .privateCloudCompute,
        isAvailable: false,
        authorization: authorization,
        reason: .systemNotReady
    )

    let result = try #require(
        FoundationModelsRuntimeInspector().privateCloudUnavailableQuotaResult(for: runtimeStatus)
    )

    #expect(result.status == .unavailable)
    #expect(result.unavailableReason == expectedReason)
}

@Test("PCC quota remains inspectable while authorized inference is unavailable")
func authorizedPCCQuotaIgnoresInferenceAvailability() {
    let runtimeStatus = FoundationModelRuntimeStatus(
        runtime: .privateCloudCompute,
        isAvailable: false,
        authorization: .granted,
        reason: .systemNotReady
    )

    let result = FoundationModelsRuntimeInspector()
        .privateCloudUnavailableQuotaResult(for: runtimeStatus)

    #expect(result == nil)
}

@Test("PCC quota preserves unsupported runtime reasons")
func unsupportedPCCQuotaPreservesRuntimeReason() throws {
    let runtimeStatus = FoundationModelRuntimeStatus(
        runtime: .privateCloudCompute,
        isSupported: false,
        isAvailable: false,
        authorization: .unknown,
        reason: .unsupportedOperatingSystem
    )

    let result = try #require(
        FoundationModelsRuntimeInspector().privateCloudUnavailableQuotaResult(for: runtimeStatus)
    )

    #expect(result.status == .unsupported)
    #expect(result.unavailableReason == .unsupportedOperatingSystem)
}

@Test("Confirmed managed entitlement makes available PCC runnable")
func grantedEntitlementMakesPCCRunnable() {
    let result = FoundationModelRuntimeStatus(
        runtime: .privateCloudCompute,
        isAvailable: true,
        authorization: .granted
    )

    #expect(result.isRunnableInCurrentProcess)
}

@Test("On-device runtime is runnable without managed PCC authorization")
func onDeviceRuntimeDoesNotRequirePCCAuthorization() {
    let result = FoundationModelRuntimeStatus(
        runtime: .onDevice,
        isAvailable: true
    )

    #expect(result.isRunnableInCurrentProcess)
    #expect(result.authorization == .notRequired)
}

@Test("Unsupported or unavailable runtimes remain non-runnable")
func unsupportedOrUnavailableRuntimesRemainNonRunnable() {
    let unavailable = FoundationModelRuntimeStatus(
        runtime: .privateCloudCompute,
        isAvailable: false,
        authorization: .granted
    )
    let unsupported = FoundationModelRuntimeStatus(
        runtime: .privateCloudCompute,
        isSupported: false,
        isAvailable: true,
        authorization: .granted
    )

    #expect(!unavailable.isRunnableInCurrentProcess)
    #expect(!unsupported.isRunnableInCurrentProcess)
}

private struct StubRuntimeInspector: FoundationModelRuntimeInspecting {
    func status(for runtime: FoundationModelRuntime) -> FoundationModelRuntimeStatus {
        switch runtime {
        case .onDevice:
            return FoundationModelRuntimeStatus(runtime: runtime, isAvailable: true)
        case .privateCloudCompute:
            return FoundationModelRuntimeStatus(
                runtime: runtime,
                isAvailable: true,
                authorization: .missing,
                reason: .missingEntitlement
            )
        }
    }

    func quotaUsage(for runtime: FoundationModelRuntime) -> FoundationModelQuotaUsage {
        switch runtime {
        case .onDevice:
            return FoundationModelQuotaUsage(runtime: runtime, status: .notApplicable)
        case .privateCloudCompute:
            return FoundationModelQuotaUsage(runtime: runtime, status: .approachingLimit)
        }
    }
}
