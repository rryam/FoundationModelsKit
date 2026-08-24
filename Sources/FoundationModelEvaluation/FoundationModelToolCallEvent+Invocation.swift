import Foundation
import FoundationModelsKit

public extension FoundationModelToolCallEvent {
    /// Converts a routed invocation into the privacy-safe event stored by evaluation traces.
    init<ToolOutcome>(
        invocation: FoundationModelToolInvocation<ToolOutcome>
    ) where ToolOutcome: Sendable {
        let eventOutcome: FoundationModelToolCallEvent.Outcome
        switch invocation.status {
        case .succeeded:
            eventOutcome = .succeeded
        case .failed:
            eventOutcome = .failed
        case .loopDetected, .invalidArguments, .budgetExceeded, .authorizationDenied,
             .confirmationRequired:
            eventOutcome = .rejected
        }
        self.init(
            sequence: invocation.sequence,
            toolName: invocation.toolName,
            outcome: eventOutcome
        )
    }
}
