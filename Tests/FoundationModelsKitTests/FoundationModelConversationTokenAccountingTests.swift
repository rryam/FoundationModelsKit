import Testing
@testable import FoundationModelsKit

@Test("A recreated session publishes context usage until generation completes")
func recreatedSessionPublishesContextUsage() {
  let contextUsage = ModelTokenUsage(
    inputTokenCount: 42,
    measurement: .tokenized,
    scope: .context
  )
  let emptyObservedUsage = ModelTokenUsage(
    input: .init(totalTokenCount: 0),
    output: .init(totalTokenCount: 0),
    measurement: .observed,
    scope: .session
  )

  let snapshot = foundationModelConversationTokenSnapshot(
    contextUsage: contextUsage,
    observedSessionUsage: emptyObservedUsage,
    usageSource: .context
  )

  #expect(snapshot.legacyTokenCount == 42)
  #expect(snapshot.usage == contextUsage)
  #expect(snapshot.usage.measurement == .tokenized)
  #expect(snapshot.usage.scope == .context)
}

@Test("Accumulated usage falls back to context when observed session usage is empty")
func accumulatedUsageFallsBackToContextWhenObservedSessionUsageIsEmpty() {
  let contextUsage = ModelTokenUsage(
    inputTokenCount: 42,
    measurement: .tokenized,
    scope: .context
  )
  let emptyObservedUsage = ModelTokenUsage(
    input: .init(totalTokenCount: 0),
    output: .init(totalTokenCount: 0),
    measurement: .observed,
    scope: .session
  )

  let snapshot = foundationModelConversationTokenSnapshot(
    contextUsage: contextUsage,
    observedSessionUsage: emptyObservedUsage,
    usageSource: .accumulatedSession
  )

  #expect(snapshot.legacyTokenCount == 42)
  #expect(snapshot.usage == contextUsage)
  #expect(snapshot.usage.scope == .context)
}

@Test("Accumulated usage prefers non-empty observed session usage")
func accumulatedUsagePrefersNonEmptyObservedSessionUsage() {
  let contextUsage = ModelTokenUsage(
    inputTokenCount: 42,
    measurement: .tokenized,
    scope: .context
  )
  let observedUsage = ModelTokenUsage(
    input: .init(totalTokenCount: 5),
    output: .init(totalTokenCount: 7),
    measurement: .observed,
    scope: .session
  )

  let snapshot = foundationModelConversationTokenSnapshot(
    contextUsage: contextUsage,
    observedSessionUsage: observedUsage,
    usageSource: .accumulatedSession
  )

  #expect(snapshot.legacyTokenCount == 42)
  #expect(snapshot.usage == observedUsage)
  #expect(snapshot.usage.scope == .session)
}
