import Foundation

public protocol FoundationModelAvailabilityChecking: Sendable {
    func currentAvailability() -> FoundationModelAvailability
    func currentAvailability(useCase: FoundationModelUseCase) -> FoundationModelAvailability
}

public extension FoundationModelAvailabilityChecking {
    func currentAvailability(useCase _: FoundationModelUseCase) -> FoundationModelAvailability {
        currentAvailability()
    }
}
