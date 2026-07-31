@preconcurrency import EventKit
import Foundation

public struct CalendarEventRecord: Codable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let startDate: Date
  public let endDate: Date
  public let location: String?
  public let calendarTitle: String
  public let notes: String?
  public let isAllDay: Bool
  public let url: URL?
  public let hasAlarms: Bool

  public init(
    id: String,
    title: String,
    startDate: Date,
    endDate: Date,
    location: String? = nil,
    calendarTitle: String,
    notes: String? = nil,
    isAllDay: Bool = false,
    url: URL? = nil,
    hasAlarms: Bool = false
  ) {
    self.id = id
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.location = location
    self.calendarTitle = calendarTitle
    self.notes = notes
    self.isAllDay = isAllDay
    self.url = url
    self.hasAlarms = hasAlarms
  }
}

public struct CalendarEventDraft: Codable, Hashable, Sendable {
  public let title: String
  public let startDate: Date
  public let endDate: Date
  public let location: String?
  public let notes: String?
  public let calendarName: String?

  public init(
    title: String,
    startDate: Date,
    endDate: Date,
    location: String? = nil,
    notes: String? = nil,
    calendarName: String? = nil
  ) {
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.location = location
    self.notes = notes
    self.calendarName = calendarName
  }
}

public struct CalendarEventChanges: Codable, Hashable, Sendable {
  public let title: String?
  public let startDate: Date?
  public let endDate: Date?
  public let location: String?
  public let notes: String?

  public init(
    title: String? = nil,
    startDate: Date? = nil,
    endDate: Date? = nil,
    location: String? = nil,
    notes: String? = nil
  ) {
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.location = location
    self.notes = notes
  }
}

public protocol CalendarReading: Sendable {
  func requestCalendarReadAccess() async throws -> Bool
  func calendarEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEventRecord]
  func calendarEvent(id: String) async throws -> CalendarEventRecord?
}

public protocol CalendarMutating: Sendable {
  func requestCalendarMutationAccess() async throws -> Bool
  func createCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEventRecord
  func updateCalendarEvent(id: String, changes: CalendarEventChanges) async throws
    -> CalendarEventRecord?
}

public actor EventKitCalendarService: CalendarReading, CalendarMutating {
  private let eventStore: EKEventStore

  public init(eventStore: EKEventStore = EKEventStore()) {
    self.eventStore = eventStore
  }

  public func requestCalendarReadAccess() async throws -> Bool {
    try await eventStore.requestFullAccessToEvents()
  }

  public func requestCalendarMutationAccess() async throws -> Bool {
    try await eventStore.requestFullAccessToEvents()
  }

  public func calendarEvents(from startDate: Date, to endDate: Date) -> [CalendarEventRecord] {
    let predicate = eventStore.predicateForEvents(
      withStart: startDate,
      end: endDate,
      calendars: eventStore.calendars(for: .event)
    )
    return eventStore.events(matching: predicate).map { Self.record($0) }
  }

  public func calendarEvent(id: String) -> CalendarEventRecord? {
    eventStore.event(withIdentifier: id).map { Self.record($0) }
  }

  public func createCalendarEvent(_ draft: CalendarEventDraft) throws -> CalendarEventRecord {
    guard draft.endDate >= draft.startDate else {
      throw ToolMutationOperationError(
        failureDescription: CalendarToolError.endBeforeStart.localizedDescription,
        commitState: .notAttempted
      )
    }

    let event = EKEvent(eventStore: eventStore)
    event.title = draft.title
    event.startDate = draft.startDate
    event.endDate = draft.endDate
    event.location = draft.location
    event.notes = draft.notes
    event.calendar = calendar(named: draft.calendarName) ?? eventStore.defaultCalendarForNewEvents

    do {
      try eventStore.save(event, span: .thisEvent)
    } catch {
      throw ToolMutationOperationError(
        failureDescription: error.localizedDescription,
        commitState: .unknown
      )
    }

    guard let identifier = event.eventIdentifier, !identifier.isEmpty else {
      throw ToolMutationOperationError(
        failureDescription: "Calendar saved the event but did not return an identifier.",
        commitState: .unknown
      )
    }

    return Self.record(event, identifier: identifier)
  }

  public func updateCalendarEvent(
    id: String,
    changes: CalendarEventChanges
  ) throws -> CalendarEventRecord? {
    guard let event = eventStore.event(withIdentifier: id) else {
      return nil
    }

    if let title = changes.title {
      event.title = title
    }
    if let startDate = changes.startDate {
      event.startDate = startDate
    }
    if let endDate = changes.endDate {
      event.endDate = endDate
    }
    if let location = changes.location {
      event.location = location
    }
    if let notes = changes.notes {
      event.notes = notes
    }

    guard event.endDate >= event.startDate else {
      throw ToolMutationOperationError(
        failureDescription: CalendarToolError.endBeforeStart.localizedDescription,
        commitState: .notAttempted
      )
    }

    do {
      try eventStore.save(event, span: .thisEvent)
    } catch {
      throw ToolMutationOperationError(
        failureDescription: error.localizedDescription,
        commitState: .unknown
      )
    }

    return Self.record(event, identifier: id)
  }

  private func calendar(named name: String?) -> EKCalendar? {
    guard let name else { return nil }
    return eventStore.calendars(for: .event).first { $0.title == name }
  }

  private static func record(_ event: EKEvent, identifier: String? = nil) -> CalendarEventRecord {
    CalendarEventRecord(
      id: identifier ?? event.eventIdentifier ?? "",
      title: event.title ?? "Untitled",
      startDate: event.startDate,
      endDate: event.endDate,
      location: event.location,
      calendarTitle: event.calendar?.title ?? "Unknown Calendar",
      notes: event.notes,
      isAllDay: event.isAllDay,
      url: event.url,
      hasAlarms: !(event.alarms?.isEmpty ?? true)
    )
  }
}
