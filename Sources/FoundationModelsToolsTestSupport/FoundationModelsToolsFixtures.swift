import Foundation
import FoundationModelsTools

/// Deterministic values for downstream tool tests and previews.
public enum FoundationModelsToolsFixtures {
  public static let date = Date(timeIntervalSince1970: 1_830_816_000)

  public static let calendarEvent = CalendarEventRecord(
    id: "calendar-event-1",
    title: "Design review",
    startDate: date,
    endDate: date.addingTimeInterval(3_600),
    location: "Studio",
    calendarTitle: "Work",
    notes: "Review the release candidate"
  )

  public static let reminder = ReminderRecord(
    id: "reminder-1",
    title: "Ship the release",
    listName: "Work",
    dueDate: date,
    priority: .high,
    notes: "Verify the tag first"
  )
}

public enum ToolMutationConfirmationFixture: Sendable {
  case approve
  case deny(reason: String? = nil)
  case fail(message: String)
}

public struct ToolMutationConfirmationFixtureError: Error, LocalizedError, Sendable {
  public let message: String

  public init(message: String) {
    self.message = message
  }

  public var errorDescription: String? {
    message
  }
}

/// A confirmer that returns scripted decisions and records every request.
public actor ScriptedToolMutationConfirmer: ToolMutationConfirming {
  private var outcomes: [ToolMutationConfirmationFixture]
  private var receivedRequests: [ToolMutationRequest] = []

  public init(_ outcomes: [ToolMutationConfirmationFixture]) {
    self.outcomes = outcomes
  }

  public init(_ outcome: ToolMutationConfirmationFixture) {
    self.init([outcome])
  }

  public func confirmation(for request: ToolMutationRequest) throws -> ToolMutationDecision {
    receivedRequests.append(request)
    let outcome =
      outcomes.isEmpty ? .deny(reason: "No scripted confirmation remains.") : outcomes.removeFirst()

    switch outcome {
    case .approve:
      return .approved()
    case .deny(let reason):
      return .denied(reason: reason)
    case .fail(let message):
      throw ToolMutationConfirmationFixtureError(message: message)
    }
  }

  public func requests() -> [ToolMutationRequest] {
    receivedRequests
  }
}

/// An in-memory Calendar service with access controls and injectable mutation failure.
public actor InMemoryCalendarService: CalendarReading, CalendarMutating {
  private var records: [String: CalendarEventRecord]
  private let readAccess: Bool
  private let mutationAccess: Bool
  private let readAccessFailure: String?
  private let mutationAccessFailure: String?
  private var nextMutationFailure: ToolMutationOperationError?
  private var mutationCalls = 0
  private var readCalls = 0
  private var generatedID = 0

  public init(
    events: [CalendarEventRecord] = [],
    readAccess: Bool = true,
    mutationAccess: Bool = true,
    readAccessFailure: String? = nil,
    mutationAccessFailure: String? = nil
  ) {
    self.records = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
    self.readAccess = readAccess
    self.mutationAccess = mutationAccess
    self.readAccessFailure = readAccessFailure
    self.mutationAccessFailure = mutationAccessFailure
  }

  public func requestCalendarReadAccess() async throws -> Bool {
    if let readAccessFailure {
      throw ToolMutationConfirmationFixtureError(message: readAccessFailure)
    }
    return readAccess
  }

  public func requestCalendarMutationAccess() async throws -> Bool {
    if let mutationAccessFailure {
      throw ToolMutationConfirmationFixtureError(message: mutationAccessFailure)
    }
    return mutationAccess
  }

  public func calendarEvents(
    from startDate: Date,
    to endDate: Date
  ) async throws -> [CalendarEventRecord] {
    readCalls += 1
    return records.values
      .filter { $0.startDate < endDate && $0.endDate >= startDate }
      .sorted { $0.startDate < $1.startDate }
  }

  public func calendarEvent(id: String) async throws -> CalendarEventRecord? {
    readCalls += 1
    return records[id]
  }

  public func createCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEventRecord {
    mutationCalls += 1
    try throwFailureIfNeeded()
    guard draft.endDate >= draft.startDate else {
      throw ToolMutationOperationError(
        failureDescription: CalendarToolError.endBeforeStart.localizedDescription,
        commitState: .notAttempted
      )
    }
    generatedID += 1
    let record = CalendarEventRecord(
      id: "calendar-generated-\(generatedID)",
      title: draft.title,
      startDate: draft.startDate,
      endDate: draft.endDate,
      location: draft.location,
      calendarTitle: draft.calendarName ?? "Default",
      notes: draft.notes
    )
    records[record.id] = record
    return record
  }

  public func updateCalendarEvent(
    id: String,
    changes: CalendarEventChanges
  ) async throws -> CalendarEventRecord? {
    mutationCalls += 1
    try throwFailureIfNeeded()
    guard let existing = records[id] else { return nil }
    let record = CalendarEventRecord(
      id: existing.id,
      title: changes.title ?? existing.title,
      startDate: changes.startDate ?? existing.startDate,
      endDate: changes.endDate ?? existing.endDate,
      location: changes.location ?? existing.location,
      calendarTitle: existing.calendarTitle,
      notes: changes.notes ?? existing.notes,
      isAllDay: existing.isAllDay,
      url: existing.url,
      hasAlarms: existing.hasAlarms
    )
    guard record.endDate >= record.startDate else {
      throw ToolMutationOperationError(
        failureDescription: CalendarToolError.endBeforeStart.localizedDescription,
        commitState: .notAttempted
      )
    }
    records[id] = record
    return record
  }

  public func setNextMutationFailure(_ failure: ToolMutationOperationError?) {
    nextMutationFailure = failure
  }

  public func mutationCallCount() -> Int {
    mutationCalls
  }

  public func readCallCount() -> Int {
    readCalls
  }

  public func events() -> [CalendarEventRecord] {
    records.values.sorted { $0.id < $1.id }
  }

  private func throwFailureIfNeeded() throws {
    guard let failure = nextMutationFailure else { return }
    nextMutationFailure = nil
    throw failure
  }
}

/// An in-memory Reminders service with access controls and injectable mutation failure.
public actor InMemoryRemindersService: RemindersReading, RemindersMutating {
  private var records: [String: ReminderRecord]
  private let readAccess: Bool
  private let mutationAccess: Bool
  private let readAccessFailure: String?
  private let mutationAccessFailure: String?
  private var nextMutationFailure: ToolMutationOperationError?
  private var mutationCalls = 0
  private var readCalls = 0
  private var generatedID = 0

  public init(
    reminders: [ReminderRecord] = [],
    readAccess: Bool = true,
    mutationAccess: Bool = true,
    readAccessFailure: String? = nil,
    mutationAccessFailure: String? = nil
  ) {
    self.records = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
    self.readAccess = readAccess
    self.mutationAccess = mutationAccess
    self.readAccessFailure = readAccessFailure
    self.mutationAccessFailure = mutationAccessFailure
  }

  public func requestRemindersReadAccess() async throws -> Bool {
    if let readAccessFailure {
      throw ToolMutationConfirmationFixtureError(message: readAccessFailure)
    }
    return readAccess
  }

  public func requestRemindersMutationAccess() async throws -> Bool {
    if let mutationAccessFailure {
      throw ToolMutationConfirmationFixtureError(message: mutationAccessFailure)
    }
    return mutationAccess
  }

  public func reminders(
    matching filter: ReminderQueryFilter,
    now: Date
  ) async throws -> [ReminderRecord] {
    readCalls += 1
    return records.values.filter { reminder in
      switch filter {
      case .all:
        true
      case .incomplete:
        !reminder.isCompleted
      case .completed:
        reminder.isCompleted
      case .today:
        !reminder.isCompleted
          && (reminder.dueDate.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false)
      case .overdue:
        !reminder.isCompleted && (reminder.dueDate.map { $0 < now } ?? false)
      }
    }
  }

  public func createReminder(_ draft: ReminderDraft) async throws -> ReminderRecord {
    mutationCalls += 1
    try throwFailureIfNeeded()
    generatedID += 1
    let record = ReminderRecord(
      id: "reminder-generated-\(generatedID)",
      title: draft.title,
      listName: draft.listName ?? "Default",
      dueDate: draft.dueDate,
      priority: draft.priority,
      notes: draft.notes
    )
    records[record.id] = record
    return record
  }

  public func completeReminder(id: String, at date: Date) async throws -> ReminderRecord? {
    mutationCalls += 1
    try throwFailureIfNeeded()
    guard let existing = records[id] else { return nil }
    let record = ReminderRecord(
      id: existing.id,
      title: existing.title,
      listName: existing.listName,
      dueDate: existing.dueDate,
      priority: existing.priority,
      notes: existing.notes,
      isCompleted: true,
      completionDate: date
    )
    records[id] = record
    return record
  }

  public func updateReminder(
    id: String,
    changes: ReminderChanges
  ) async throws -> ReminderRecord? {
    mutationCalls += 1
    try throwFailureIfNeeded()
    guard let existing = records[id] else { return nil }
    let dueDate = changes.clearDueDate ? nil : changes.dueDate ?? existing.dueDate
    let record = ReminderRecord(
      id: existing.id,
      title: changes.title ?? existing.title,
      listName: existing.listName,
      dueDate: dueDate,
      priority: changes.priority ?? existing.priority,
      notes: changes.notes ?? existing.notes,
      isCompleted: existing.isCompleted,
      completionDate: existing.completionDate
    )
    records[id] = record
    return record
  }

  public func deleteReminder(id: String) async throws -> ReminderRecord? {
    mutationCalls += 1
    try throwFailureIfNeeded()
    return records.removeValue(forKey: id)
  }

  public func setNextMutationFailure(_ failure: ToolMutationOperationError?) {
    nextMutationFailure = failure
  }

  public func mutationCallCount() -> Int {
    mutationCalls
  }

  public func readCallCount() -> Int {
    readCalls
  }

  public func reminders() -> [ReminderRecord] {
    records.values.sorted { $0.id < $1.id }
  }

  private func throwFailureIfNeeded() throws {
    guard let failure = nextMutationFailure else { return }
    nextMutationFailure = nil
    throw failure
  }
}
