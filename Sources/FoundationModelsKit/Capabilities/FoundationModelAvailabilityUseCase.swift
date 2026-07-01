import Foundation

public struct FoundationModelAvailabilityUseCase: Sendable {
    public static let descriptor = FoundationModelCapabilityDescriptor(
        id: "foundation-models.check-availability",
        displayName: "Check Model Availability",
        summary: "Checks whether Apple Intelligence is currently available."
    )

    private let checker: any FoundationModelAvailabilityChecking

    public init(checker: any FoundationModelAvailabilityChecking = FoundationModelsModelAvailabilityChecker()) {
        self.checker = checker
    }

    public func execute(
        useCase: FoundationModelUseCase = .general
    ) -> FoundationModelAvailability {
        checker.currentAvailability(useCase: useCase)
    }
}
