import Foundation

/// A cancellation-safe serialized lane shared by Foundation Models sessions and coordinators.
public actor FoundationModelExecutionGate {
    private struct WaitingExecution {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    /// The process-wide gate used by execution coordinators unless the app injects another lane.
    public static let shared = FoundationModelExecutionGate()

    private var isExecuting = false
    private var waitingExecutions: [WaitingExecution] = []

    public init() {}

    /// Runs an operation after every earlier operation on this gate has released the lane.
    public func perform<Output: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        let executionID = UUID()
        try await acquire(id: executionID)

        do {
            let output = try await operation()
            release()
            return output
        } catch {
            release()
            throw error
        }
    }

    private func acquire(id: UUID) async throws {
        try Task.checkCancellation()

        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isExecuting {
                    waitingExecutions.append(
                        WaitingExecution(id: id, continuation: continuation)
                    )
                } else {
                    isExecuting = true
                    continuation.resume(returning: true)
                }
            }
        } onCancel: {
            Task { await self.cancelWaitingExecution(id: id) }
        }

        guard acquired else { throw CancellationError() }
        if Task.isCancelled {
            release()
            throw CancellationError()
        }
    }

    private func cancelWaitingExecution(id: UUID) {
        guard let index = waitingExecutions.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waitingExecution = waitingExecutions.remove(at: index)
        waitingExecution.continuation.resume(returning: false)
    }

    private func release() {
        guard !waitingExecutions.isEmpty else {
            isExecuting = false
            return
        }
        let nextExecution = waitingExecutions.removeFirst()
        nextExecution.continuation.resume(returning: true)
    }
}
