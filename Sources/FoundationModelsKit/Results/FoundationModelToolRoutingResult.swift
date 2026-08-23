import Foundation

/// The typed successful outcomes recorded during one model turn.
public enum FoundationModelToolRoutingResult<Outcome: Sendable>: Sendable {
    case none
    case one(Outcome)
    case many([Outcome])
}

extension FoundationModelToolRoutingResult: Equatable where Outcome: Equatable {}
