import Foundation
import FoundationModels

public struct FoundationModelsRuntimeInspector: FoundationModelRuntimeInspecting {
    public init() {}

    public func status(for runtime: FoundationModelRuntime) -> FoundationModelRuntimeStatus {
        switch runtime {
        case .onDevice:
            return onDeviceStatus()
        case .privateCloudCompute:
            return privateCloudStatus()
        }
    }

    public func quotaUsage(for runtime: FoundationModelRuntime) -> FoundationModelQuotaUsage {
        switch runtime {
        case .onDevice:
            return FoundationModelQuotaUsage(
                runtime: .onDevice,
                status: .notApplicable,
                metadata: metadata(for: .onDevice)
            )
        case .privateCloudCompute:
            return privateCloudQuotaUsage()
        }
    }

    private func onDeviceStatus() -> FoundationModelRuntimeStatus {
        let availability = FoundationModelsModelAvailabilityChecker().currentAvailability()
        return FoundationModelRuntimeStatus(
            runtime: .onDevice,
            isAvailable: availability.isAvailable,
            reason: availability.reason.map(Self.runtimeReason),
            metadata: metadata(for: .onDevice)
        )
    }

    private func privateCloudStatus() -> FoundationModelRuntimeStatus {
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            switch model.availability {
            case .available:
                let authorization = PrivateCloudComputeEntitlementChecker().authorization()
                return FoundationModelRuntimeStatus(
                    runtime: .privateCloudCompute,
                    isAvailable: true,
                    authorization: authorization,
                    metadata: metadata(for: .privateCloudCompute)
                )
            case .unavailable(let reason):
                return FoundationModelRuntimeStatus(
                    runtime: .privateCloudCompute,
                    isAvailable: false,
                    authorization: PrivateCloudComputeEntitlementChecker().authorization(),
                    reason: Self.runtimeReason(reason),
                    metadata: metadata(for: .privateCloudCompute)
                )
            }
        }

        return unsupportedPrivateCloudStatus(reason: .unsupportedOperatingSystem)
        #else
        return unsupportedPrivateCloudStatus(reason: .unsupportedToolchain)
        #endif
    }

    private func privateCloudQuotaUsage() -> FoundationModelQuotaUsage {
        let status = privateCloudStatus()
        if let unavailableResult = privateCloudUnavailableQuotaResult(for: status) {
            return unavailableResult
        }

        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *) {
            return quotaResult(PrivateCloudComputeLanguageModel().quotaUsage)
        }
        #endif

        return FoundationModelQuotaUsage(
            runtime: .privateCloudCompute,
            status: .unsupported,
            unavailableReason: .unsupportedToolchain,
            metadata: metadata(for: .privateCloudCompute)
        )
    }

    func privateCloudUnavailableQuotaResult(
        for status: FoundationModelRuntimeStatus
    ) -> FoundationModelQuotaUsage? {
        guard status.runtime == .privateCloudCompute else { return nil }
        guard status.isSupported else {
            return FoundationModelQuotaUsage(
                runtime: .privateCloudCompute,
                status: .unsupported,
                unavailableReason: status.reason ?? .unknown,
                metadata: metadata(for: .privateCloudCompute)
            )
        }

        let authorizationReason: FoundationModelRuntimeUnavailableReason
        switch status.authorization {
        case .granted:
            return nil
        case .missing:
            authorizationReason = .missingEntitlement
        case .unknown, .notRequired:
            authorizationReason = .unknown
        }

        return FoundationModelQuotaUsage(
            runtime: .privateCloudCompute,
            status: .unavailable,
            unavailableReason: authorizationReason,
            metadata: metadata(for: .privateCloudCompute)
        )
    }

    private func unsupportedPrivateCloudStatus(
        reason: FoundationModelRuntimeUnavailableReason
    ) -> FoundationModelRuntimeStatus {
        FoundationModelRuntimeStatus(
            runtime: .privateCloudCompute,
            isSupported: false,
            isAvailable: false,
            authorization: .unknown,
            reason: reason,
            metadata: metadata(for: .privateCloudCompute)
        )
    }

    private func metadata(for runtime: FoundationModelRuntime) -> FoundationModelExecutionMetadata {
        FoundationModelExecutionMetadata(
            provider: "Foundation Models",
            modelIdentifier: runtime == .onDevice ? "system" : "pcc"
        )
    }

    private static func runtimeReason(
        _ reason: FoundationModelAvailabilityUnavailableReason
    ) -> FoundationModelRuntimeUnavailableReason {
        switch reason {
        case .deviceNotEligible:
            return .deviceNotEligible
        case .appleIntelligenceNotEnabled:
            return .appleIntelligenceNotEnabled
        case .modelNotReady:
            return .modelNotReady
        case .unknown:
            return .unknown
        }
    }
}

#if compiler(>=6.4)
@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
private extension FoundationModelsRuntimeInspector {
    static func runtimeReason(
        _ reason: PrivateCloudComputeLanguageModel.Availability.UnavailableReason
    ) -> FoundationModelRuntimeUnavailableReason {
        switch reason {
        case .deviceNotEligible:
            return .deviceNotEligible
        case .systemNotReady:
            return .systemNotReady
        @unknown default:
            return .unknown
        }
    }

    func quotaResult(
        _ usage: PrivateCloudComputeLanguageModel.QuotaUsage
    ) -> FoundationModelQuotaUsage {
        let status: FoundationModelQuotaStatus
        switch usage.status {
        case .belowLimit(let details):
            status = details.isApproachingLimit ? .approachingLimit : .belowLimit
        case .limitReached:
            status = .limitReached
        @unknown default:
            status = .unavailable
        }

        return FoundationModelQuotaUsage(
            runtime: .privateCloudCompute,
            status: status,
            resetDate: usage.resetDate,
            canRequestLimitIncrease: usage.limitIncreaseSuggestion != nil,
            metadata: metadata(for: .privateCloudCompute)
        )
    }
}
#endif
