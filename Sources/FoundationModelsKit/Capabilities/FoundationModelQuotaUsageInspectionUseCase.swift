import Foundation

public struct FoundationModelQuotaUsageInspectionUseCase: Sendable {
    public static let descriptor = FoundationModelCapabilityDescriptor(
        id: "foundation-models.inspect-quota-usage",
        displayName: "Inspect Model Quota Usage",
        summary: "Reports Private Cloud Compute quota state without inventing numeric usage."
    )

    private let inspector: any FoundationModelRuntimeInspecting

    public init(inspector: any FoundationModelRuntimeInspecting = FoundationModelsRuntimeInspector()) {
        self.inspector = inspector
    }

    public func execute(
        runtimes: [FoundationModelRuntime] = FoundationModelRuntime.allCases
    ) -> [FoundationModelQuotaUsage] {
        runtimes.map(inspector.quotaUsage(for:))
    }
}
