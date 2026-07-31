import Foundation
import FoundationModels
import FoundationModelsKit

/// Read-only Calendar access. This tool cannot create or update events.
public struct CalendarReadTool: Tool {
  public let name = "readCalendar"
  public let description = "Query calendar events or read one event by identifier"

  @Generable
  public struct Arguments: RuntimeCompatibleGenerable {
    @Guide(description: "The read action to perform: 'query' or 'read'")
    public var action: String

    @Guide(description: "Number of upcoming days to query")
    public var daysAhead: Int?

    @Guide(description: "Event identifier for the read action")
    public var eventId: String?

    public init(
      action: String = "",
      daysAhead: Int? = nil,
      eventId: String? = nil
    ) {
      self.action = action
      self.daysAhead = daysAhead
      self.eventId = eventId
    }
  }

  private let service: any CalendarReading
  private let now: @Sendable () -> Date

  public init(
    service: any CalendarReading,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.service = service
    self.now = now
  }

  public func call(arguments: Arguments) async throws -> GeneratedContent {
    let authorized: Bool
    do {
      authorized = try await service.requestCalendarReadAccess()
    } catch {
      throw CalendarToolError.accessDenied
    }
    guard authorized else {
      throw CalendarToolError.accessDenied
    }

    switch arguments.action.lowercased() {
    case "query":
      return try await query(daysAhead: arguments.daysAhead ?? 7)
    case "read":
      return try await read(eventID: arguments.eventId)
    default:
      throw CalendarToolError.invalidReadAction
    }
  }

  private func query(daysAhead: Int) async throws -> GeneratedContent {
    let startDate = now()
    guard let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: startDate)
    else {
      throw CalendarToolError.invalidEndDate
    }

    let events = try await service.calendarEvents(from: startDate, to: endDate)
    let description = Self.formatEventQueryResults(events)

    return GeneratedContent(properties: [
      "status": "success",
      "count": events.count,
      "daysQueried": daysAhead,
      "eventIds": events.map(\.id),
      "events": description.isEmpty
        ? "No events found in the next \(daysAhead) days"
        : description.trimmingCharacters(in: .whitespacesAndNewlines),
      "message": "Found \(events.count) event(s) in the next \(daysAhead) days"
    ])
  }

  private func read(eventID: String?) async throws -> GeneratedContent {
    guard let eventID, !eventID.isEmpty else {
      throw CalendarToolError.missingEventID
    }
    guard let event = try await service.calendarEvent(id: eventID) else {
      throw CalendarToolError.eventNotFound
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .full
    dateFormatter.timeStyle = .short

    return GeneratedContent(properties: [
      "status": "success",
      "eventId": event.id,
      "title": event.title,
      "startDate": CalendarToolDateFormatter.string(from: event.startDate),
      "endDate": CalendarToolDateFormatter.string(from: event.endDate),
      "location": event.location ?? "",
      "notes": event.notes ?? "",
      "calendar": event.calendarTitle,
      "isAllDay": event.isAllDay,
      "url": event.url?.absoluteString ?? "",
      "hasAlarms": event.hasAlarms,
      "formattedDate":
        "\(dateFormatter.string(from: event.startDate)) - \(dateFormatter.string(from: event.endDate))"
    ])
  }

  static func formatEventQueryResults(_ events: [CalendarEventRecord]) -> String {
    events.enumerated().map { index, event in
      let dateFormatter = DateFormatter()
      dateFormatter.dateStyle = .medium
      dateFormatter.timeStyle = .short

      var lines = [
        "\(index + 1). \(event.title)",
        "   Event ID: \(event.id)",
        "   When: \(dateFormatter.string(from: event.startDate)) - "
          + dateFormatter.string(from: event.endDate),
        "   Calendar: \(event.calendarTitle)"
          + (event.location.map { " at \($0)" } ?? "")
      ]
      if let notes = event.notes, !notes.isEmpty {
        lines.append("   Notes: \(notes.prefix(50))...")
      }
      return lines.joined(separator: "\n")
    }.joined(separator: "\n\n")
  }
}

/// Calendar mutations guarded by an app-owned confirmation provider.
public struct CalendarMutationTool: Tool {
  public let name = "mutateCalendar"
  public let description = "Create or update a calendar event after host-app confirmation"

  @Generable
  public struct Arguments: RuntimeCompatibleGenerable {
    @Guide(description: "The mutation action to perform: 'create' or 'update'")
    public var action: String

    @Guide(description: "Event title for creating or updating")
    public var title: String?

    @Guide(description: "Start date in format YYYY-MM-DD HH:mm:ss")
    public var startDate: String?

    @Guide(description: "End date in format YYYY-MM-DD HH:mm:ss")
    public var endDate: String?

    @Guide(description: "Event location")
    public var location: String?

    @Guide(description: "Event notes")
    public var notes: String?

    @Guide(description: "Calendar name; the default calendar is used when omitted")
    public var calendarName: String?

    @Guide(description: "Event identifier for the update action")
    public var eventId: String?

    public init(
      action: String = "",
      title: String? = nil,
      startDate: String? = nil,
      endDate: String? = nil,
      location: String? = nil,
      notes: String? = nil,
      calendarName: String? = nil,
      eventId: String? = nil
    ) {
      self.action = action
      self.title = title
      self.startDate = startDate
      self.endDate = endDate
      self.location = location
      self.notes = notes
      self.calendarName = calendarName
      self.eventId = eventId
    }
  }

  private enum PreparedMutation: Sendable {
    case create(CalendarEventDraft)
    case update(id: String, changes: CalendarEventChanges)
  }

  private let service: any CalendarMutating
  private let executor: ToolMutationExecutor

  public init(
    service: any CalendarMutating,
    confirmation: any ToolMutationConfirming
  ) {
    self.service = service
    self.executor = ToolMutationExecutor(confirmer: confirmation)
  }

  init(service: any CalendarMutating, executor: ToolMutationExecutor) {
    self.service = service
    self.executor = executor
  }

  public func execute(
    arguments: Arguments
  ) async throws -> ToolMutationExecution<CalendarEventRecord> {
    let prepared = try prepare(arguments)
    let request = mutationRequest(for: prepared)
    let service = service

    return try await executor.execute(
      request,
      resourceID: { $0.id },
      operation: {
        let authorized: Bool
        do {
          authorized = try await service.requestCalendarMutationAccess()
        } catch {
          throw ToolMutationOperationError(
            failureDescription: error.localizedDescription,
            commitState: .notAttempted
          )
        }

        guard authorized else {
          throw ToolMutationOperationError(
            failureDescription: CalendarToolError.accessDenied.localizedDescription,
            commitState: .notAttempted
          )
        }

        do {
          switch prepared {
          case .create(let draft):
            return try await service.createCalendarEvent(draft)
          case .update(let id, let changes):
            guard let event = try await service.updateCalendarEvent(id: id, changes: changes) else {
              throw ToolMutationOperationError(
                failureDescription: CalendarToolError.eventNotFound.localizedDescription,
                commitState: .notAttempted
              )
            }
            return event
          }
        } catch let error as ToolMutationOperationError {
          throw error
        } catch {
          throw ToolMutationOperationError(
            failureDescription: error.localizedDescription,
            commitState: .unknown
          )
        }
      }
    )
  }

  public func call(arguments: Arguments) async throws -> GeneratedContent {
    let execution = try await execute(arguments: arguments)
    let event = execution.value
    let action = execution.receipt.request.action

    return GeneratedContent(properties: [
      "status": "success",
      "message": action == "create" ? "Event created successfully" : "Event updated successfully",
      "receiptId": execution.receipt.request.id.uuidString,
      "receiptStatus": execution.receipt.status.rawValue,
      "commitState": execution.receipt.commitState.rawValue,
      "eventId": event.id,
      "title": event.title,
      "startDate": CalendarToolDateFormatter.string(from: event.startDate),
      "endDate": CalendarToolDateFormatter.string(from: event.endDate),
      "location": event.location ?? "",
      "calendar": event.calendarTitle
    ])
  }

  private func prepare(_ arguments: Arguments) throws -> PreparedMutation {
    switch arguments.action.lowercased() {
    case "create":
      guard let title = arguments.title?.trimmingCharacters(in: .whitespacesAndNewlines),
        !title.isEmpty
      else {
        throw CalendarToolError.missingTitle
      }
      guard let startDateText = arguments.startDate,
        let startDate = CalendarToolDateFormatter.date(from: startDateText)
      else {
        throw CalendarToolError.invalidStartDate
      }

      let endDate: Date
      if let endDateText = arguments.endDate {
        guard let parsed = CalendarToolDateFormatter.date(from: endDateText) else {
          throw CalendarToolError.invalidEndDate
        }
        endDate = parsed
      } else {
        endDate = startDate.addingTimeInterval(3_600)
      }
      guard endDate >= startDate else {
        throw CalendarToolError.endBeforeStart
      }

      return .create(
        CalendarEventDraft(
          title: title,
          startDate: startDate,
          endDate: endDate,
          location: arguments.location,
          notes: arguments.notes,
          calendarName: arguments.calendarName
        )
      )
    case "update":
      guard let eventID = arguments.eventId, !eventID.isEmpty else {
        throw CalendarToolError.missingEventID
      }
      guard
        arguments.title != nil || arguments.startDate != nil || arguments.endDate != nil
          || arguments.location != nil || arguments.notes != nil
      else {
        throw CalendarToolError.noChanges
      }
      let startDate = try parseOptional(arguments.startDate, error: .invalidStartDate)
      let endDate = try parseOptional(arguments.endDate, error: .invalidEndDate)
      if let startDate, let endDate, endDate < startDate {
        throw CalendarToolError.endBeforeStart
      }
      return .update(
        id: eventID,
        changes: CalendarEventChanges(
          title: arguments.title,
          startDate: startDate,
          endDate: endDate,
          location: arguments.location,
          notes: arguments.notes
        )
      )
    default:
      throw CalendarToolError.invalidMutationAction
    }
  }

  private func parseOptional(
    _ value: String?,
    error: CalendarToolError
  ) throws -> Date? {
    guard let value else { return nil }
    guard let date = CalendarToolDateFormatter.date(from: value) else {
      throw error
    }
    return date
  }

  private func mutationRequest(for mutation: PreparedMutation) -> ToolMutationRequest {
    switch mutation {
    case .create(let draft):
      ToolMutationRequest(
        toolName: name,
        action: "create",
        summary: "Create calendar event '\(draft.title)' from "
          + "\(CalendarToolDateFormatter.string(from: draft.startDate)) to "
          + CalendarToolDateFormatter.string(from: draft.endDate),
        details: mutationDetails(for: draft)
      )
    case .update(let id, let changes):
      ToolMutationRequest(
        toolName: name,
        action: "update",
        summary: "Update calendar event '\(changes.title ?? id)'",
        details: mutationDetails(for: changes),
        resourceID: id
      )
    }
  }

  private func mutationDetails(for draft: CalendarEventDraft) -> [ToolMutationDetail] {
    [
      ToolMutationDetail(label: "Title", value: draft.title),
      ToolMutationDetail(
        label: "Start",
        value: CalendarToolDateFormatter.string(from: draft.startDate)
      ),
      ToolMutationDetail(
        label: "End",
        value: CalendarToolDateFormatter.string(from: draft.endDate)
      ),
      optionalDetail(label: "Location", value: draft.location),
      optionalDetail(label: "Notes", value: draft.notes),
      optionalDetail(label: "Calendar", value: draft.calendarName)
    ].compactMap { $0 }
  }

  private func mutationDetails(for changes: CalendarEventChanges) -> [ToolMutationDetail] {
    [
      optionalDetail(label: "Title", value: changes.title),
      changes.startDate.map {
        ToolMutationDetail(label: "Start", value: CalendarToolDateFormatter.string(from: $0))
      },
      changes.endDate.map {
        ToolMutationDetail(label: "End", value: CalendarToolDateFormatter.string(from: $0))
      },
      optionalDetail(label: "Location", value: changes.location),
      optionalDetail(label: "Notes", value: changes.notes)
    ].compactMap { $0 }
  }

  private func optionalDetail(label: String, value: String?) -> ToolMutationDetail? {
    value.map { ToolMutationDetail(label: label, value: $0) }
  }
}

/// Backward-compatible combined Calendar tool. New code should register split read and mutation tools.
@available(
  *,
  deprecated,
  message:
    "Use CalendarReadTool and CalendarMutationTool so mutations require explicit confirmation."
)
public struct CalendarTool: Tool {
  public let name = "manageCalendar"
  public let description = "Read calendar events; mutations require host-app confirmation"

  @Generable
  public struct Arguments: RuntimeCompatibleGenerable {
    @Guide(description: "The action: 'create', 'query', 'read', or 'update'")
    public var action: String
    @Guide(description: "Event title") public var title: String?
    @Guide(description: "Start date in format YYYY-MM-DD HH:mm:ss") public var startDate: String?
    @Guide(description: "End date in format YYYY-MM-DD HH:mm:ss") public var endDate: String?
    @Guide(description: "Event location") public var location: String?
    @Guide(description: "Event notes") public var notes: String?
    @Guide(description: "Calendar name") public var calendarName: String?
    @Guide(description: "Number of upcoming days to query") public var daysAhead: Int?
    @Guide(description: "Event identifier") public var eventId: String?

    public init(
      action: String = "",
      title: String? = nil,
      startDate: String? = nil,
      endDate: String? = nil,
      location: String? = nil,
      notes: String? = nil,
      calendarName: String? = nil,
      daysAhead: Int? = nil,
      eventId: String? = nil
    ) {
      self.action = action
      self.title = title
      self.startDate = startDate
      self.endDate = endDate
      self.location = location
      self.notes = notes
      self.calendarName = calendarName
      self.daysAhead = daysAhead
      self.eventId = eventId
    }
  }

  private let readTool: CalendarReadTool
  private let mutationTool: CalendarMutationTool?

  public init() {
    let service = EventKitCalendarService()
    self.readTool = CalendarReadTool(service: service)
    self.mutationTool = nil
  }

  public init(
    readService: any CalendarReading,
    mutationService: any CalendarMutating,
    confirmation: any ToolMutationConfirming
  ) {
    self.readTool = CalendarReadTool(service: readService)
    self.mutationTool = CalendarMutationTool(
      service: mutationService,
      confirmation: confirmation
    )
  }

  public init(confirmation: any ToolMutationConfirming) {
    let service = EventKitCalendarService()
    self.init(
      readService: service,
      mutationService: service,
      confirmation: confirmation
    )
  }

  public func call(arguments: Arguments) async throws -> some PromptRepresentable {
    switch arguments.action.lowercased() {
    case "query", "read":
      return try await readTool.call(
        arguments: CalendarReadTool.Arguments(
          action: arguments.action,
          daysAhead: arguments.daysAhead,
          eventId: arguments.eventId
        )
      )
    case "create", "update":
      guard let mutationTool else {
        throw ToolMutationExecutionError.confirmationRequired(
          for: ToolMutationRequest(
            toolName: "mutateCalendar",
            action: arguments.action.lowercased(),
            summary: "Calendar mutation requested by deprecated CalendarTool",
            resourceID: arguments.eventId
          )
        )
      }
      return try await mutationTool.call(
        arguments: CalendarMutationTool.Arguments(
          action: arguments.action,
          title: arguments.title,
          startDate: arguments.startDate,
          endDate: arguments.endDate,
          location: arguments.location,
          notes: arguments.notes,
          calendarName: arguments.calendarName,
          eventId: arguments.eventId
        )
      )
    default:
      throw CalendarToolError.invalidAction
    }
  }

  static func formatEventQueryResults(_ events: [CalendarEventRecord]) -> String {
    CalendarReadTool.formatEventQueryResults(events)
  }
}

public enum CalendarToolError: Error, LocalizedError, Sendable {
  case accessDenied
  case invalidAction
  case invalidReadAction
  case invalidMutationAction
  case missingTitle
  case invalidStartDate
  case invalidEndDate
  case endBeforeStart
  case noChanges
  case missingEventID
  case eventNotFound

  public var errorDescription: String? {
    switch self {
    case .accessDenied:
      "Access to Calendar was denied. Grant permission in Settings."
    case .invalidAction:
      "Invalid action. Use 'create', 'query', 'read', or 'update'."
    case .invalidReadAction:
      "Invalid read action. Use 'query' or 'read'."
    case .invalidMutationAction:
      "Invalid mutation action. Use 'create' or 'update'."
    case .missingTitle:
      "Title is required to create an event."
    case .invalidStartDate:
      "Invalid start date format. Use YYYY-MM-DD HH:mm:ss."
    case .invalidEndDate:
      "Invalid end date format. Use YYYY-MM-DD HH:mm:ss."
    case .endBeforeStart:
      "The event end date cannot be earlier than its start date."
    case .noChanges:
      "At least one event field is required for an update."
    case .missingEventID:
      "Event ID is required."
    case .eventNotFound:
      "Event not found with the provided ID."
    }
  }
}

private enum CalendarToolDateFormatter {
  static func date(from value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = .current
    return formatter.date(from: value)
  }

  static func string(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = .current
    return formatter.string(from: date)
  }
}

typealias CalendarEventSummary = CalendarEventRecord
typealias CalendarError = CalendarToolError
