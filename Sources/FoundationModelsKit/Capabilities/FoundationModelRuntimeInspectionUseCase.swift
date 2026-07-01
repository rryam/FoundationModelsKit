import Foundation

public struct FoundationModelRuntimeInspectionUseCase: Sendable {
    public static let descriptor = FoundationModelCapabilityDescriptor(
        id: "foundation-models.inspect-runtime",
        displayName: "Inspect Model Runtime",
        summary: "Reports availability for on-device and Private Cloud Compute models."
    )

    private let inspector: any FoundationModelRuntimeInspecting

    public init(inspector: any FoundationModelRuntimeInspecting = FoundationModelsRuntimeInspector()) {
        self.inspector = inspector
    }

    public func execute(
        runtimes: [FoundationModelRuntime] = FoundationModelRuntime.allCases
    ) -> [FoundationModelRuntimeStatus] {
        runtimes.map(inspector.status(for:))
    }
}
