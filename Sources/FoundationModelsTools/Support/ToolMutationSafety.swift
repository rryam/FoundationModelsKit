import Foundation

/// Whether a tool mutation reached durable system state.
public enum ToolMutationCommitState: String, Codable, Hashable, Sendable {
  /// The mutation operation was never invoked.
  case notAttempted
  /// The service confirmed that the mutation committed.
  case committed
  /// The service confirmed that the mutation did not commit.
  case notCommitted
  /// The service failed after execution began and cannot prove whether it committed.
  case unknown
}

/// The terminal status recorded for a tool mutation request.
public enum ToolMutationReceiptStatus: String, Codable, Hashable, Sendable {
  case confirmationRequired
  case denied
  case succeeded
  case failed
}

/// An app-reviewable description of a proposed real-world mutation.
public struct ToolMutationDetail: Codable, Hashable, Sendable {
  public let label: String
  public let value: String

  public init(label: String, value: String) {
    self.label = label
    self.value = value
  }
}

/// An app-reviewable description of a proposed real-world mutation.
public struct ToolMutationRequest: Codable, Hashable, Sendable {
  public let id: UUID
  public let toolName: String
  public let action: String
  public let summary: String
  public let details: [ToolMutationDetail]
  public let resourceID: String?
  public let isDestructive: Bool

  public init(
    id: UUID = UUID(),
    toolName: String,
    action: String,
    summary: String,
    details: [ToolMutationDetail] = [],
    resourceID: String? = nil,
    isDestructive: Bool = false
  ) {
    self.id = id
    self.toolName = toolName
    self.action = action
    self.summary = summary
    self.details = details
    self.resourceID = resourceID
    self.isDestructive = isDestructive
  }
}

/// An app-owned decision about a proposed tool mutation.
public struct ToolMutationDecision: Codable, Hashable, Sendable {
  public let isApproved: Bool
  public let reason: String?

  public init(isApproved: Bool, reason: String? = nil) {
    self.isApproved = isApproved
    self.reason = reason
  }

  public static func approved() -> Self {
    Self(isApproved: true)
  }

  public static func denied(reason: String? = nil) -> Self {
    Self(isApproved: false, reason: reason)
  }
}

/// Implemented by the host app so model-authored arguments cannot approve their own mutation.
public protocol ToolMutationConfirming: Sendable {
  func confirmation(for request: ToolMutationRequest) async throws -> ToolMutationDecision
}

/// Adapts an app-owned async closure into a mutation confirmer.
public struct ToolMutationConfirmationHandler: ToolMutationConfirming {
  private let handler: @Sendable (ToolMutationRequest) async throws -> ToolMutationDecision

  public init(
    _ handler: @escaping @Sendable (ToolMutationRequest) async throws -> ToolMutationDecision
  ) {
    self.handler = handler
  }

  public func confirmation(for request: ToolMutationRequest) async throws -> ToolMutationDecision {
    try await handler(request)
  }
}

/// A durable, truthful account of what happened to a proposed mutation.
public struct ToolMutationReceipt: Codable, Hashable, Sendable {
  public let request: ToolMutationRequest
  public let status: ToolMutationReceiptStatus
  public let commitState: ToolMutationCommitState
  public let message: String
  public let resourceID: String?
  public let timestamp: Date

  public init(
    request: ToolMutationRequest,
    status: ToolMutationReceiptStatus,
    commitState: ToolMutationCommitState,
    message: String,
    resourceID: String? = nil,
    timestamp: Date = Date()
  ) {
    self.request = request
    self.status = status
    self.commitState = commitState
    self.message = message
    self.resourceID = resourceID
    self.timestamp = timestamp
  }
}

/// The typed value and receipt returned after a confirmed mutation commits.
public struct ToolMutationExecution<Value: Sendable>: Sendable {
  public let value: Value
  public let receipt: ToolMutationReceipt

  public init(value: Value, receipt: ToolMutationReceipt) {
    self.value = value
    self.receipt = receipt
  }
}

/// A mutation failure carrying the receipt that callers should persist or display.
public struct ToolMutationExecutionError: Error, LocalizedError, Sendable {
  public let receipt: ToolMutationReceipt

  public init(receipt: ToolMutationReceipt) {
    self.receipt = receipt
  }

  public var errorDescription: String? {
    receipt.message
  }

  public static func confirmationRequired(for request: ToolMutationRequest) -> Self {
    Self(
      receipt: ToolMutationReceipt(
        request: request,
        status: .confirmationRequired,
        commitState: .notAttempted,
        message: "The host app must explicitly confirm this mutation before it can run."
      )
    )
  }
}

/// An error a service can throw when it knows whether a failed operation committed.
public struct ToolMutationOperationError: Error, LocalizedError, Sendable {
  public let failureDescription: String
  public let commitState: ToolMutationCommitState

  public init(
    failureDescription: String,
    commitState: ToolMutationCommitState
  ) {
    self.failureDescription = failureDescription
    self.commitState = commitState
  }

  public var errorDescription: String? {
    failureDescription
  }
}

/// Executes mutations only after an app-owned confirmer approves the exact request.
public struct ToolMutationExecutor: Sendable {
  private let confirmer: any ToolMutationConfirming
  private let now: @Sendable () -> Date

  public init(
    confirmer: any ToolMutationConfirming,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.confirmer = confirmer
    self.now = now
  }

  public func execute<Value: Sendable>(
    _ request: ToolMutationRequest,
    resourceID: @escaping @Sendable (Value) -> String? = { _ in nil },
    operation: @escaping @Sendable () async throws -> Value
  ) async throws -> ToolMutationExecution<Value> {
    let decision: ToolMutationDecision

    do {
      decision = try await confirmer.confirmation(for: request)
    } catch {
      throw failure(
        request: request,
        message: "Confirmation failed: \(error.localizedDescription)",
        commitState: .notAttempted
      )
    }

    guard decision.isApproved else {
      throw ToolMutationExecutionError(
        receipt: ToolMutationReceipt(
          request: request,
          status: .denied,
          commitState: .notAttempted,
          message: decision.reason ?? "The host app denied this mutation.",
          timestamp: now()
        )
      )
    }

    do {
      let value = try await operation()
      let receipt = ToolMutationReceipt(
        request: request,
        status: .succeeded,
        commitState: .committed,
        message: "Mutation committed successfully.",
        resourceID: resourceID(value) ?? request.resourceID,
        timestamp: now()
      )
      return ToolMutationExecution(value: value, receipt: receipt)
    } catch let error as ToolMutationOperationError {
      throw failure(
        request: request,
        message: error.failureDescription,
        commitState: error.commitState
      )
    } catch {
      throw failure(
        request: request,
        message: error.localizedDescription,
        commitState: .unknown
      )
    }
  }

  private func failure(
    request: ToolMutationRequest,
    message: String,
    commitState: ToolMutationCommitState
  ) -> ToolMutationExecutionError {
    ToolMutationExecutionError(
      receipt: ToolMutationReceipt(
        request: request,
        status: .failed,
        commitState: commitState,
        message: message,
        timestamp: now()
      )
    )
  }
}
