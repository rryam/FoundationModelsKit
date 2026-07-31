@preconcurrency import EventKit
import Foundation

public enum ReminderQueryFilter: String, Codable, Hashable, Sendable {
  case all
  case incomplete
  case completed
  case today
  case overdue
}

public enum ReminderPriority: String, Codable, Hashable, Sendable {
  case none
  case low
  case medium
  case high

  var eventKitValue: Int {
    switch self {
    case .none: 0
    case .low: 9
    case .medium: 5
    case .high: 1
    }
  }

  init(eventKitValue: Int) {
    switch eventKitValue {
    case 1...3: self = .high
    case 4...6: self = .medium
    case 7...9: self = .low
    default: self = .none
    }
  }
}

public struct ReminderRecord: Codable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let listName: String
  public let dueDate: Date?
  public let priority: ReminderPriority
  public let notes: String?
  public let isCompleted: Bool
  public let completionDate: Date?

  public init(
    id: String,
    title: String,
    listName: String,
    dueDate: Date? = nil,
    priority: ReminderPriority = .none,
    notes: String? = nil,
    isCompleted: Bool = false,
    completionDate: Date? = nil
  ) {
    self.id = id
    self.title = title
    self.listName = listName
    self.dueDate = dueDate
    self.priority = priority
    self.notes = notes
    self.isCompleted = isCompleted
    self.completionDate = completionDate
  }
}

public struct ReminderDraft: Codable, Hashable, Sendable {
  public let title: String
  public let notes: String?
  public let dueDate: Date?
  public let priority: ReminderPriority
  public let listName: String?

  public init(
    title: String,
    notes: String? = nil,
    dueDate: Date? = nil,
    priority: ReminderPriority = .none,
    listName: String? = nil
  ) {
    self.title = title
    self.notes = notes
    self.dueDate = dueDate
    self.priority = priority
    self.listName = listName
  }
}

public struct ReminderChanges: Codable, Hashable, Sendable {
  public let title: String?
  public let notes: String?
  public let dueDate: Date?
  public let clearDueDate: Bool
  public let priority: ReminderPriority?

  public init(
    title: String? = nil,
    notes: String? = nil,
    dueDate: Date? = nil,
    clearDueDate: Bool = false,
    priority: ReminderPriority? = nil
  ) {
    self.title = title
    self.notes = notes
    self.dueDate = dueDate
    self.clearDueDate = clearDueDate
    self.priority = priority
  }
}

public protocol RemindersReading: Sendable {
  func requestRemindersReadAccess() async throws -> Bool
  func reminders(matching filter: ReminderQueryFilter, now: Date) async throws -> [ReminderRecord]
}

public protocol RemindersMutating: Sendable {
  func requestRemindersMutationAccess() async throws -> Bool
  func createReminder(_ draft: ReminderDraft) async throws -> ReminderRecord
  func completeReminder(id: String, at date: Date) async throws -> ReminderRecord?
  func updateReminder(id: String, changes: ReminderChanges) async throws -> ReminderRecord?
  func deleteReminder(id: String) async throws -> ReminderRecord?
}

public actor EventKitRemindersService: RemindersReading, RemindersMutating {
  private let eventStore: EKEventStore

  public init(eventStore: EKEventStore = EKEventStore()) {
    self.eventStore = eventStore
  }

  public func requestRemindersReadAccess() async throws -> Bool {
    try await eventStore.requestFullAccessToReminders()
  }

  public func requestRemindersMutationAccess() async throws -> Bool {
    try await eventStore.requestFullAccessToReminders()
  }

  public func reminders(
    matching filter: ReminderQueryFilter,
    now: Date
  ) async -> [ReminderRecord] {
    let calendars = eventStore.calendars(for: .reminder)
    let predicate: NSPredicate

    switch filter {
    case .all:
      predicate = eventStore.predicateForReminders(in: calendars)
    case .completed:
      predicate = eventStore.predicateForCompletedReminders(
        withCompletionDateStarting: nil,
        ending: nil,
        calendars: calendars
      )
    case .today:
      let startOfDay = Calendar.current.startOfDay(for: now)
      let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? now
      predicate = eventStore.predicateForIncompleteReminders(
        withDueDateStarting: startOfDay,
        ending: endOfDay,
        calendars: calendars
      )
    case .overdue:
      predicate = eventStore.predicateForIncompleteReminders(
        withDueDateStarting: nil,
        ending: now,
        calendars: calendars
      )
    case .incomplete:
      predicate = eventStore.predicateForIncompleteReminders(
        withDueDateStarting: nil,
        ending: nil,
        calendars: calendars
      )
    }

    return await withCheckedContinuation { continuation in
      eventStore.fetchReminders(matching: predicate) { reminders in
        continuation.resume(returning: reminders?.map(Self.record) ?? [])
      }
    }
  }

  public func createReminder(_ draft: ReminderDraft) throws -> ReminderRecord {
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = draft.title
    reminder.notes = draft.notes
    reminder.dueDateComponents = Self.dateComponents(draft.dueDate)
    reminder.priority = draft.priority.eventKitValue
    reminder.calendar = list(named: draft.listName) ?? eventStore.defaultCalendarForNewReminders()

    try save(reminder)

    guard !reminder.calendarItemIdentifier.isEmpty else {
      throw ToolMutationOperationError(
        failureDescription: "Reminders saved the item but did not return an identifier.",
        commitState: .unknown
      )
    }

    return Self.record(reminder)
  }

  public func completeReminder(id: String, at date: Date) throws -> ReminderRecord? {
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      return nil
    }

    reminder.isCompleted = true
    reminder.completionDate = date
    try save(reminder)
    return Self.record(reminder)
  }

  public func updateReminder(
    id: String,
    changes: ReminderChanges
  ) throws -> ReminderRecord? {
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      return nil
    }

    if let title = changes.title {
      reminder.title = title
    }
    if let notes = changes.notes {
      reminder.notes = notes
    }
    if changes.clearDueDate {
      reminder.dueDateComponents = nil
    } else if let dueDate = changes.dueDate {
      reminder.dueDateComponents = Self.dateComponents(dueDate)
    }
    if let priority = changes.priority {
      reminder.priority = priority.eventKitValue
    }

    try save(reminder)
    return Self.record(reminder)
  }

  public func deleteReminder(id: String) throws -> ReminderRecord? {
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      return nil
    }

    let record = Self.record(reminder)
    do {
      try eventStore.remove(reminder, commit: true)
    } catch {
      throw ToolMutationOperationError(
        failureDescription: error.localizedDescription,
        commitState: .unknown
      )
    }
    return record
  }

  private func list(named name: String?) -> EKCalendar? {
    guard let name else { return nil }
    return eventStore.calendars(for: .reminder).first { $0.title == name }
  }

  private func save(_ reminder: EKReminder) throws {
    do {
      try eventStore.save(reminder, commit: true)
    } catch {
      throw ToolMutationOperationError(
        failureDescription: error.localizedDescription,
        commitState: .unknown
      )
    }
  }

  private static func dateComponents(_ date: Date?) -> DateComponents? {
    guard let date else { return nil }
    return Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: date
    )
  }

  private static func record(_ reminder: EKReminder) -> ReminderRecord {
    ReminderRecord(
      id: reminder.calendarItemIdentifier,
      title: reminder.title ?? "Untitled",
      listName: reminder.calendar?.title ?? "Unknown List",
      dueDate: reminder.dueDateComponents?.date,
      priority: ReminderPriority(eventKitValue: reminder.priority),
      notes: reminder.notes,
      isCompleted: reminder.isCompleted,
      completionDate: reminder.completionDate
    )
  }
}
