import Foundation
import FoundationModelsTools
import FoundationModelsToolsTestSupport
import Testing

@Suite("Tool Mutation Safety")
struct ToolMutationSafetyTests {
  private let fixedDate = FoundationModelsToolsFixtures.date

  @Test("Calendar reads do not require mutation confirmation")
  func calendarReadDoesNotRequireConfirmation() async throws {
    let service = InMemoryCalendarService(events: [FoundationModelsToolsFixtures.calendarEvent])
    let tool = CalendarReadTool(service: service, now: { FoundationModelsToolsFixtures.date })

    _ = try await tool.call(arguments: .init(action: "query", daysAhead: 1))

    #expect(await service.readCallCount() == 1)
    #expect(await service.mutationCallCount() == 0)
  }

  @Test("Calendar reads preserve long query ranges")
  func calendarReadPreservesLongRanges() async throws {
    let service = InMemoryCalendarService()
    let tool = CalendarReadTool(service: service, now: { FoundationModelsToolsFixtures.date })

    _ = try await tool.call(arguments: .init(action: "query", daysAhead: 730))

    #expect(await service.readCallCount() == 1)
  }

  @Test("Calendar read access errors normalize to the stable tool error")
  func calendarReadAccessErrorIsNormalized() async throws {
    let service = InMemoryCalendarService(readAccessFailure: "EventKit unavailable")
    let tool = CalendarReadTool(service: service)

    do {
      _ = try await tool.call(arguments: .init(action: "query"))
      Issue.record("Expected read access to fail")
    } catch let error as CalendarToolError {
      guard case .accessDenied = error else {
        Issue.record("Expected accessDenied, got \(error)")
        return
      }
    }
  }

  @Test("Denied Calendar mutation never reaches the service")
  func deniedCalendarMutationDoesNotExecute() async throws {
    let service = InMemoryCalendarService()
    let confirmer = ScriptedToolMutationConfirmer(.deny(reason: "User cancelled."))
    let tool = CalendarMutationTool(service: service, confirmation: confirmer)

    do {
      _ = try await tool.execute(arguments: calendarCreateArguments)
      Issue.record("Expected the mutation to be denied")
    } catch let error as ToolMutationExecutionError {
      #expect(error.receipt.status == .denied)
      #expect(error.receipt.commitState == .notAttempted)
      #expect(error.receipt.message == "User cancelled.")
    }

    #expect(await service.mutationCallCount() == 0)
    #expect(await confirmer.requests().count == 1)
  }

  @Test("Approved Calendar mutation returns a committed receipt")
  func approvedCalendarMutationCommits() async throws {
    let service = InMemoryCalendarService()
    let confirmer = ScriptedToolMutationConfirmer(.approve)
    let tool = CalendarMutationTool(service: service, confirmation: confirmer)

    let execution = try await tool.execute(arguments: calendarCreateArguments)

    #expect(execution.receipt.status == .succeeded)
    #expect(execution.receipt.commitState == .committed)
    #expect(execution.receipt.resourceID == execution.value.id)
    #expect(execution.value.title == "Safety review")
    #expect(await service.mutationCallCount() == 1)
    #expect(await service.events().count == 1)
    let details = try #require(await confirmer.requests().first?.details)
    #expect(details.contains(ToolMutationDetail(label: "Title", value: "Safety review")))
    #expect(details.contains { $0.label == "Start" })
    #expect(details.contains { $0.label == "End" })
  }

  @Test("Calendar service failure preserves its known commit state")
  func calendarFailureReceiptIsTruthful() async throws {
    let service = InMemoryCalendarService()
    await service.setNextMutationFailure(
      ToolMutationOperationError(
        failureDescription: "Database rejected the event.",
        commitState: .notCommitted
      )
    )
    let tool = CalendarMutationTool(
      service: service,
      confirmation: ScriptedToolMutationConfirmer(.approve)
    )

    do {
      _ = try await tool.execute(arguments: calendarCreateArguments)
      Issue.record("Expected the service failure")
    } catch let error as ToolMutationExecutionError {
      #expect(error.receipt.status == .failed)
      #expect(error.receipt.commitState == .notCommitted)
      #expect(error.receipt.message == "Database rejected the event.")
    }
  }

  @Test("Approved Calendar update targets the confirmed event")
  func approvedCalendarUpdateCommits() async throws {
    let original = FoundationModelsToolsFixtures.calendarEvent
    let service = InMemoryCalendarService(events: [original])
    let confirmer = ScriptedToolMutationConfirmer(.approve)
    let tool = CalendarMutationTool(service: service, confirmation: confirmer)

    let execution = try await tool.execute(
      arguments: .init(
        action: "update",
        title: "Final design review",
        eventId: original.id
      )
    )

    #expect(execution.receipt.commitState == .committed)
    #expect(execution.receipt.resourceID == original.id)
    #expect(execution.value.title == "Final design review")
    #expect(await confirmer.requests().first?.resourceID == original.id)
  }

  @Test("Confirmation failure is not reported as an attempted mutation")
  func confirmationFailureDoesNotExecute() async throws {
    let service = InMemoryCalendarService()
    let confirmer = ScriptedToolMutationConfirmer(.fail(message: "Confirmation UI unavailable."))
    let tool = CalendarMutationTool(service: service, confirmation: confirmer)

    do {
      _ = try await tool.execute(arguments: calendarCreateArguments)
      Issue.record("Expected confirmation to fail")
    } catch let error as ToolMutationExecutionError {
      #expect(error.receipt.status == .failed)
      #expect(error.receipt.commitState == .notAttempted)
      #expect(error.receipt.message.contains("Confirmation UI unavailable"))
    }

    #expect(await service.mutationCallCount() == 0)
  }

  @available(*, deprecated)
  @Test("Deprecated Calendar tool fails closed without app confirmation")
  func combinedCalendarToolFailsClosed() async throws {
    let tool = CalendarTool()

    do {
      _ = try await tool.call(
        arguments: .init(
          action: "create",
          title: "Must not be written",
          startDate: "2028-01-09 10:00:00"
        )
      )
      Issue.record("Expected explicit confirmation to be required")
    } catch let error as ToolMutationExecutionError {
      #expect(error.receipt.status == .confirmationRequired)
      #expect(error.receipt.commitState == .notAttempted)
    }
  }

  @Test("Denied Reminder deletion is marked destructive and never executes")
  func deniedReminderDeletionDoesNotExecute() async throws {
    let service = InMemoryRemindersService(reminders: [FoundationModelsToolsFixtures.reminder])
    let confirmer = ScriptedToolMutationConfirmer(.deny(reason: "Keep it."))
    let tool = RemindersMutationTool(service: service, confirmation: confirmer)

    do {
      _ = try await tool.execute(
        arguments: .init(action: "delete", reminderId: FoundationModelsToolsFixtures.reminder.id)
      )
      Issue.record("Expected deletion to be denied")
    } catch let error as ToolMutationExecutionError {
      #expect(error.receipt.status == .denied)
      #expect(error.receipt.commitState == .notAttempted)
      #expect(error.receipt.request.isDestructive)
    }

    #expect(await service.mutationCallCount() == 0)
    #expect(await service.reminders().count == 1)
  }

  @Test("Approved Reminder completion records the exact completion time")
  func approvedReminderCompletionCommits() async throws {
    let service = InMemoryRemindersService(reminders: [FoundationModelsToolsFixtures.reminder])
    let confirmer = ScriptedToolMutationConfirmer(.approve)
    let tool = RemindersMutationTool(
      service: service,
      confirmation: confirmer,
      now: { FoundationModelsToolsFixtures.date }
    )

    let execution = try await tool.execute(
      arguments: .init(action: "complete", reminderId: FoundationModelsToolsFixtures.reminder.id)
    )

    #expect(execution.receipt.commitState == .committed)
    #expect(execution.value.isCompleted)
    #expect(execution.value.completionDate == fixedDate)
    #expect(await service.mutationCallCount() == 1)
  }

  @Test("Reminder creation accepts none as no due date")
  func reminderCreationAcceptsNoneDueDate() async throws {
    let service = InMemoryRemindersService()
    let tool = RemindersMutationTool(
      service: service,
      confirmation: ScriptedToolMutationConfirmer(.approve)
    )

    let execution = try await tool.execute(
      arguments: .init(action: "create", title: "No deadline", dueDate: "none")
    )

    #expect(execution.value.dueDate == nil)
    #expect(execution.receipt.commitState == .committed)
    #expect(execution.receipt.resourceID == execution.value.id)
  }

  @Test("Malformed Reminder due dates fail before confirmation")
  func malformedReminderDueDateDoesNotConfirmOrExecute() async throws {
    let service = InMemoryRemindersService(reminders: [FoundationModelsToolsFixtures.reminder])
    let confirmer = ScriptedToolMutationConfirmer(.approve)
    let tool = RemindersMutationTool(service: service, confirmation: confirmer)

    do {
      _ = try await tool.execute(
        arguments: .init(
          action: "update",
          title: "Other valid change",
          dueDate: "not-a-date",
          reminderId: FoundationModelsToolsFixtures.reminder.id
        )
      )
      Issue.record("Expected invalid due date to fail")
    } catch let error as RemindersToolError {
      guard case .invalidDueDate = error else {
        Issue.record("Expected invalidDueDate, got \(error)")
        return
      }
    }

    #expect(await confirmer.requests().isEmpty)
    #expect(await service.mutationCallCount() == 0)
  }

  @Test("Approved Reminder create, update, and delete use one confirmation per mutation")
  func reminderMutationLifecycleCommits() async throws {
    let service = InMemoryRemindersService()
    let confirmer = ScriptedToolMutationConfirmer([.approve, .approve, .approve])
    let tool = RemindersMutationTool(
      service: service,
      confirmation: confirmer,
      now: { FoundationModelsToolsFixtures.date }
    )

    let created = try await tool.execute(
      arguments: .init(
        action: "create",
        title: "Verify release",
        dueDate: "2028-01-09 10:00:00",
        priority: "high",
        listName: "Work"
      )
    )
    let updated = try await tool.execute(
      arguments: .init(
        action: "update",
        title: "Verify release tag",
        dueDate: "none",
        priority: "medium",
        reminderId: created.value.id
      )
    )
    let deleted = try await tool.execute(
      arguments: .init(action: "delete", reminderId: created.value.id)
    )

    #expect(created.receipt.commitState == .committed)
    #expect(updated.value.title == "Verify release tag")
    #expect(updated.value.dueDate == nil)
    #expect(updated.value.priority == .medium)
    #expect(deleted.receipt.request.isDestructive)
    #expect(await service.reminders().isEmpty)
    #expect(await service.mutationCallCount() == 3)
    #expect(await confirmer.requests().count == 3)
  }

  @Test("Reminder reads do not require mutation confirmation")
  func reminderReadDoesNotRequireConfirmation() async throws {
    let service = InMemoryRemindersService(reminders: [FoundationModelsToolsFixtures.reminder])
    let tool = RemindersReadTool(service: service, now: { FoundationModelsToolsFixtures.date })

    _ = try await tool.call(arguments: .init(filter: "all"))

    #expect(await service.readCallCount() == 1)
    #expect(await service.mutationCallCount() == 0)
  }

  @Test("Unknown Reminder filters preserve the incomplete fallback")
  func unknownReminderFilterFallsBackToIncomplete() async throws {
    let service = InMemoryRemindersService(reminders: [FoundationModelsToolsFixtures.reminder])
    let tool = RemindersReadTool(service: service, now: { FoundationModelsToolsFixtures.date })

    _ = try await tool.call(arguments: .init(filter: "typo"))

    #expect(await service.readCallCount() == 1)
  }

  @Test("Reminders read access errors normalize to the stable tool error")
  func remindersReadAccessErrorIsNormalized() async throws {
    let service = InMemoryRemindersService(readAccessFailure: "EventKit unavailable")
    let tool = RemindersReadTool(service: service)

    do {
      _ = try await tool.call(arguments: .init())
      Issue.record("Expected read access to fail")
    } catch let error as RemindersToolError {
      guard case .accessDenied = error else {
        Issue.record("Expected accessDenied, got \(error)")
        return
      }
    }
  }

  @Test("In-memory today filter excludes completed reminders")
  func reminderFixtureTodayFilterMatchesProduction() async throws {
    let incomplete = FoundationModelsToolsFixtures.reminder
    let completed = ReminderRecord(
      id: "completed-today",
      title: "Already done",
      listName: "Work",
      dueDate: fixedDate,
      isCompleted: true,
      completionDate: fixedDate
    )
    let service = InMemoryRemindersService(reminders: [incomplete, completed])

    let matches = try await service.reminders(matching: .today, now: fixedDate)

    #expect(matches.map(\.id) == [incomplete.id])
  }

  @Test("In-memory Calendar matches production date validation")
  func calendarFixtureMatchesProductionDateValidation() async throws {
    let original = FoundationModelsToolsFixtures.calendarEvent
    let service = InMemoryCalendarService(events: [original])

    do {
      _ = try await service.updateCalendarEvent(
        id: original.id,
        changes: CalendarEventChanges(
          endDate: original.startDate.addingTimeInterval(-60)
        )
      )
      Issue.record("Expected invalid date order to fail")
    } catch let error as ToolMutationOperationError {
      #expect(error.commitState == .notAttempted)
      #expect(error.failureDescription.contains("earlier"))
    }

    #expect(await service.events().first == original)
  }

  @Test("In-memory Calendar rejects invalid creates before persistence")
  func calendarFixtureRejectsInvalidCreateDates() async throws {
    let service = InMemoryCalendarService()
    let draft = CalendarEventDraft(
      title: "Invalid",
      startDate: fixedDate,
      endDate: fixedDate.addingTimeInterval(-60)
    )

    do {
      _ = try await service.createCalendarEvent(draft)
      Issue.record("Expected invalid date order to fail")
    } catch let error as ToolMutationOperationError {
      #expect(error.commitState == .notAttempted)
    }

    #expect(await service.events().isEmpty)
  }

  @available(*, deprecated)
  @Test("Deprecated Reminders tool fails closed without app confirmation")
  func combinedRemindersToolFailsClosed() async throws {
    let tool = RemindersTool()

    do {
      _ = try await tool.call(arguments: .init(action: "delete", reminderId: "must-not-delete"))
      Issue.record("Expected explicit confirmation to be required")
    } catch let error as ToolMutationExecutionError {
      #expect(error.receipt.status == .confirmationRequired)
      #expect(error.receipt.commitState == .notAttempted)
      #expect(error.receipt.request.isDestructive)
    }
  }

  @Test("Reminders access denial produces a not-attempted failure receipt")
  func remindersAccessDenialIsNotAttempted() async throws {
    let service = InMemoryRemindersService(mutationAccess: false)
    let tool = RemindersMutationTool(
      service: service,
      confirmation: ScriptedToolMutationConfirmer(.approve)
    )

    do {
      _ = try await tool.execute(arguments: .init(action: "create", title: "No access"))
      Issue.record("Expected access denial")
    } catch let error as ToolMutationExecutionError {
      #expect(error.receipt.status == .failed)
      #expect(error.receipt.commitState == .notAttempted)
      #expect(error.receipt.message.contains("denied"))
    }

    #expect(await service.mutationCallCount() == 0)
  }

  @Test("Mutation receipts round-trip through Codable")
  func receiptCodableRoundTrip() throws {
    let request = ToolMutationRequest(
      id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
      toolName: "mutateReminders",
      action: "delete",
      summary: "Delete reminder",
      resourceID: "reminder-1",
      isDestructive: true
    )
    let receipt = ToolMutationReceipt(
      request: request,
      status: .denied,
      commitState: .notAttempted,
      message: "User denied the request.",
      resourceID: "reminder-1",
      timestamp: fixedDate
    )

    let data = try JSONEncoder().encode(receipt)
    let decoded = try JSONDecoder().decode(ToolMutationReceipt.self, from: data)

    #expect(decoded == receipt)
  }

  private var calendarCreateArguments: CalendarMutationTool.Arguments {
    .init(
      action: "create",
      title: "Safety review",
      startDate: "2028-01-09 10:00:00",
      endDate: "2028-01-09 11:00:00",
      calendarName: "Work"
    )
  }
}
