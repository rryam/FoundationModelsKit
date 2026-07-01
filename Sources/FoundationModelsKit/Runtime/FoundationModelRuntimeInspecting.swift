import Foundation

public protocol FoundationModelRuntimeInspecting: Sendable {
    func status(for runtime: FoundationModelRuntime) -> FoundationModelRuntimeStatus
    func quotaUsage(for runtime: FoundationModelRuntime) -> FoundationModelQuotaUsage
}
