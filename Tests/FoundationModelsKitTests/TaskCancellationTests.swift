import Testing
@testable import FoundationModelsKit

@Test("Caller cancellation propagates to owned task")
func valuePropagatesCallerCancellationToOwnedTask() async {
  let ownedTask = Task<Void, Error> {
    try await Task.sleep(for: .seconds(30))
  }
  let caller = Task<Void, Error> {
    try await ownedTask.valuePropagatingCancellation()
  }

  await Task.yield()
  caller.cancel()

  do {
    try await caller.value
    Issue.record("Expected caller cancellation to throw")
  } catch is CancellationError {
    #expect(ownedTask.isCancelled)
  } catch {
    Issue.record("Expected CancellationError, received \(error)")
  }
}
