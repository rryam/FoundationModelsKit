import Foundation

/// Collects ordered tool decisions and routes successful results into an app-defined outcome type.
public actor FoundationModelToolResultRouter<Outcome: Sendable> {
    private struct InvocationRecord: Sendable {
        let toolName: String
        let arguments: FoundationModelToolValue
        let identifier: UUID
        let status: FoundationModelToolInvocation<Outcome>.Status
        let outcome: Outcome?
        let failure: FoundationModelErrorProjection?
        let recordedAt: Date
    }

    private let argumentRecording: FoundationModelToolArgumentRecording
    private var recordedInvocations: [FoundationModelToolInvocation<Outcome>] = []

    public init(argumentRecording: FoundationModelToolArgumentRecording = .fingerprintOnly) {
        self.argumentRecording = argumentRecording
    }

    /// Records a decision returned by ``FoundationModelToolExecutionPolicy``.
    ///
    /// The mapping closure runs only when the policy result is `succeeded`.
    @discardableResult
    public func record<Output: Sendable>(
        tool toolName: String,
        arguments: FoundationModelToolValue,
        result: FoundationModelToolExecutionResult<Output>,
        identifier: UUID = UUID(),
        recordedAt: Date = Date(),
        mapSuccess: @Sendable (Output) -> Outcome
    ) throws -> FoundationModelToolInvocation<Outcome> {
        switch result {
        case .succeeded(let output, _, _):
            return try append(InvocationRecord(
                toolName: toolName,
                arguments: arguments,
                identifier: identifier,
                status: .succeeded,
                outcome: mapSuccess(output),
                failure: nil,
                recordedAt: recordedAt
            ))
        case .loopDetected:
            return try appendPolicyDecision(
                toolName: toolName,
                arguments: arguments,
                identifier: identifier,
                status: .loopDetected,
                recordedAt: recordedAt
            )
        case .invalidArguments:
            return try appendPolicyDecision(
                toolName: toolName,
                arguments: arguments,
                identifier: identifier,
                status: .invalidArguments,
                recordedAt: recordedAt
            )
        case .budgetExceeded:
            return try appendPolicyDecision(
                toolName: toolName,
                arguments: arguments,
                identifier: identifier,
                status: .budgetExceeded,
                recordedAt: recordedAt
            )
        case .confirmationRequired:
            return try appendPolicyDecision(
                toolName: toolName,
                arguments: arguments,
                identifier: identifier,
                status: .confirmationRequired,
                recordedAt: recordedAt
            )
        }
    }

    /// Records a successful tool call that did not run through the generic execution policy.
    @discardableResult
    public func recordSuccess(
        tool toolName: String,
        arguments: FoundationModelToolValue,
        outcome: Outcome,
        identifier: UUID = UUID(),
        recordedAt: Date = Date()
    ) throws -> FoundationModelToolInvocation<Outcome> {
        try append(InvocationRecord(
            toolName: toolName,
            arguments: arguments,
            identifier: identifier,
            status: .succeeded,
            outcome: outcome,
            failure: nil,
            recordedAt: recordedAt
        ))
    }

    /// Records a thrown tool failure without retaining the error or its message.
    @discardableResult
    public func recordFailure(
        tool toolName: String,
        arguments: FoundationModelToolValue,
        failure: FoundationModelErrorProjection? = nil,
        identifier: UUID = UUID(),
        recordedAt: Date = Date()
    ) throws -> FoundationModelToolInvocation<Outcome> {
        try append(InvocationRecord(
            toolName: toolName,
            arguments: arguments,
            identifier: identifier,
            status: .failed,
            outcome: nil,
            failure: failure,
            recordedAt: recordedAt
        ))
    }

    /// Returns a value copy of every finalized invocation in actor insertion order.
    public func snapshot() -> [FoundationModelToolInvocation<Outcome>] {
        recordedInvocations
    }

    /// Returns only successful typed outcomes without choosing between multiple tool calls.
    public func routingResult() -> FoundationModelToolRoutingResult<Outcome> {
        let outcomes = recordedInvocations.compactMap(\.outcome)
        switch outcomes.count {
        case 0:
            return .none
        case 1:
            return .one(outcomes[0])
        default:
            return .many(outcomes)
        }
    }

    private func appendPolicyDecision(
        toolName: String,
        arguments: FoundationModelToolValue,
        identifier: UUID,
        status: FoundationModelToolInvocation<Outcome>.Status,
        recordedAt: Date
    ) throws -> FoundationModelToolInvocation<Outcome> {
        try append(InvocationRecord(
            toolName: toolName,
            arguments: arguments,
            identifier: identifier,
            status: status,
            outcome: nil,
            failure: nil,
            recordedAt: recordedAt
        ))
    }

    private func append(
        _ record: InvocationRecord
    ) throws -> FoundationModelToolInvocation<Outcome> {
        let canonicalArguments = try record.arguments.canonicalJSONData()
        let invocation = FoundationModelToolInvocation(
            sequence: recordedInvocations.count,
            identifier: record.identifier,
            toolName: record.toolName,
            argumentFingerprint: Self.fingerprint(canonicalArguments),
            arguments: argumentRecording == .includeArguments ? record.arguments : nil,
            status: record.status,
            outcome: record.outcome,
            failure: record.failure,
            recordedAt: record.recordedAt
        )
        recordedInvocations.append(invocation)
        return invocation
    }

    private static func fingerprint(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
