import Foundation
import Testing
@testable import FoundationModelsKit

@Suite("Tool execution policy")
struct FoundationModelToolExecutionPolicyTests {
  @Test func rejectsMissingRequiredAndOutOfRangeValues() async {
    let policy = FoundationModelToolExecutionPolicy()
    let schema = FoundationModelToolSchema(type: "object", properties: ["count": .init(type: "integer", minimum: 1, maximum: 3)], required: ["count"])
    await #expect(throws: FoundationModelToolExecutionFailure.self) {
      try await policy.execute(tool: "count", arguments: .object([:]), schema: schema) { 1 }
    }
  }

  @Test func detectsRepeatedIdenticalCalls() async throws {
    let policy = FoundationModelToolExecutionPolicy()
    let schema = FoundationModelToolSchema(type: "object")
    _ = try await policy.execute(tool: "read", arguments: .object([:]), schema: schema) { 1 }
    await #expect(throws: FoundationModelToolExecutionFailure.self) {
      try await policy.execute(tool: "read", arguments: .object([:]), schema: schema) { 2 }
    }
  }

  @Test func requiresHostConfirmationForSideEffects() async {
    let policy = FoundationModelToolExecutionPolicy()
    let schema = FoundationModelToolSchema(type: "object")
    await #expect(throws: FoundationModelToolExecutionFailure.self) {
      try await policy.execute(tool: "delete", arguments: .object([:]), schema: schema, sideEffect: .confirmation) { 1 }
    }
  }
}
