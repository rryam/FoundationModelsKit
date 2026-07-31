import Foundation
import FoundationModels
import FoundationModelsKit

/// Read-only Reminders access. This tool cannot create, update, complete, or delete reminders.
public struct RemindersReadTool: Tool {
  public let name = "readReminders"
  public let description = "Query reminders with an optional status or date filter"

  @Generable
  public struct Arguments: RuntimeCompatibleGenerable {
    @Guide(description: "Filter: 'all', 'incomplete', 'completed', 'today', or 'overdue'")
    public var filter: String?

    public init(filter: String? = nil) {
      self.filter = filter
    }
  }

  private let service: any RemindersReading
  private let now: @Sendable () -> Date

  public init(
    service: any RemindersReading,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.service = service
    self.now = now
  }

  public func call(arguments: Arguments) async throws -> GeneratedContent {
    let authorized: Bool
    do {
      authorized = try await service.requestRemindersReadAccess()
    } catch {
      throw RemindersToolError.accessDenied
    }
    guard authorized else {
      throw RemindersToolError.accessDenied
    }

    let filter = Self.filter(from: arguments.filter)
    var reminders = try await service.reminders(matching: filter, now: now())
    reminders.sort(by: Self.sort)
    let description = Self.formatReminderQueryResults(reminders)

    return GeneratedContent(properties: [
      "status": "success",
      "filter": filter.rawValue,
      "count": reminders.count,
      "reminderIds": reminders.map(\.id),
      "reminders": description.isEmpty
        ? "No reminders found with filter '\(filter.rawValue)'"
        : description.trimmingCharacters(in: .whitespacesAndNewlines),
      "message": "Found \(reminders.count) reminder(s)"
    ])
  }

  private static func filter(from value: String?) -> ReminderQueryFilter {
    guard let value else { return .incomplete }
    return ReminderQueryFilter(rawValue: value.lowercased()) ?? .incomplete
  }

  private static func sort(_ lhs: ReminderRecord, _ rhs: ReminderRecord) -> Bool {
    if lhs.isCompleted != rhs.isCompleted {
      return !lhs.isCompleted
    }
    if let lhsDate = lhs.dueDate, let rhsDate = rhs.dueDate {
      return lhsDate < rhsDate
    }
    return lhs.dueDate != nil && rhs.dueDate == nil
  }

  static func formatReminderQueryResults(_ reminders: [ReminderRecord]) -> String {
    reminders.enumerated().map { index, reminder in
      var lines = [
        "\(index + 1). \(reminder.isCompleted ? "[x]" : "[ ]") \(reminder.title)",
        "   Reminder ID: \(reminder.id)",
        "   List: \(reminder.listName)"
      ]
      if let dueDate = reminder.dueDate {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append("   Due: \(formatter.string(from: dueDate))")
      }
      if reminder.priority != .none {
        lines.append("   Priority: \(reminder.priority.rawValue.capitalized)")
      }
      if let notes = reminder.notes, !notes.isEmpty {
        lines.append("   Notes: \(notes.prefix(50))...")
      }
      return lines.joined(separator: "\n")
    }.joined(separator: "\n\n")
  }
}

/// Reminders mutations guarded by an app-owned confirmation provider.
public struct RemindersMutationTool: Tool {
  public let name = "mutateReminders"
  public let description =
    "Create, update, complete, or delete a reminder after host-app confirmation"

  @Generable
  public struct Arguments: RuntimeCompatibleGenerable {
    @Guide(description: "The mutation action: 'create', 'complete', 'update', or 'delete'")
    public var action: String

    @Guide(description: "Reminder title")
    public var title: String?

    @Guide(description: "Reminder notes")
    public var notes: String?

    @Guide(description: "Due date in format YYYY-MM-DD HH:mm:ss, or 'none' when updating")
    public var dueDate: String?

    @Guide(description: "Priority: 'none', 'low', 'medium', or 'high'")
    public var priority: String?

    @Guide(description: "Reminder list name; the default list is used when omitted")
    public var listName: String?

    @Guide(description: "Reminder identifier for complete, update, or delete")
    public var reminderId: String?

    public init(
      action: String = "",
      title: String? = nil,
      notes: String? = nil,
      dueDate: String? = nil,
      priority: String? = nil,
      listName: String? = nil,
      reminderId: String? = nil
    ) {
      self.action = action
      self.title = title
      self.notes = notes
      self.dueDate = dueDate
      self.priority = priority
      self.listName = listName
      self.reminderId = reminderId
    }
  }

  private enum PreparedMutation: Sendable {
    case create(ReminderDraft)
    case complete(id: String)
    case update(id: String, changes: ReminderChanges)
    case delete(id: String)
  }

  private let service: any RemindersMutating
  private let executor: ToolMutationExecutor
  private let now: @Sendable () -> Date

  public init(
    service: any RemindersMutating,
    confirmation: any ToolMutationConfirming,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.service = service
    self.executor = ToolMutationExecutor(confirmer: confirmation, now: now)
    self.now = now
  }

  init(
    service: any RemindersMutating,
    executor: ToolMutationExecutor,
    now: @escaping @Sendable () -> Date
  ) {
    self.service = service
    self.executor = executor
    self.now = now
  }

  public func execute(
    arguments: Arguments
  ) async throws -> ToolMutationExecution<ReminderRecord> {
    let prepared = try prepare(arguments)
    let request = mutationRequest(for: prepared)
    let service = service
    let now = now

    return try await executor.execute(
      request,
      resourceID: { $0.id },
      operation: {
        let authorized: Bool
        do {
          authorized = try await service.requestRemindersMutationAccess()
        } catch {
          throw ToolMutationOperationError(
            failureDescription: error.localizedDescription,
            commitState: .notAttempted
          )
        }

        guard authorized else {
          throw ToolMutationOperationError(
            failureDescription: RemindersToolError.accessDenied.localizedDescription,
            commitState: .notAttempted
          )
        }

        do {
          let record: ReminderRecord?
          switch prepared {
          case .create(let draft):
            record = try await service.createReminder(draft)
          case .complete(let id):
            record = try await service.completeReminder(id: id, at: now())
          case .update(let id, let changes):
            record = try await service.updateReminder(id: id, changes: changes)
          case .delete(let id):
            record = try await service.deleteReminder(id: id)
          }

          guard let record else {
            throw ToolMutationOperationError(
              failureDescription: RemindersToolError.reminderNotFound.localizedDescription,
              commitState: .notAttempted
            )
          }
          return record
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
    let reminder = execution.value
    let action = execution.receipt.request.action

    return GeneratedContent(properties: [
      "status": "success",
      "message": Self.successMessage(for: action),
      "receiptId": execution.receipt.request.id.uuidString,
      "receiptStatus": execution.receipt.status.rawValue,
      "commitState": execution.receipt.commitState.rawValue,
      "reminderId": reminder.id,
      "title": reminder.title,
      "list": reminder.listName,
      "dueDate": RemindersToolDateFormatter.string(from: reminder.dueDate),
      "priority": reminder.priority.rawValue.capitalized,
      "completedAt": RemindersToolDateFormatter.string(from: reminder.completionDate)
    ])
  }

  private func prepare(_ arguments: Arguments) throws -> PreparedMutation {
    switch arguments.action.lowercased() {
    case "create":
      guard let title = arguments.title?.trimmingCharacters(in: .whitespacesAndNewlines),
        !title.isEmpty
      else {
        throw RemindersToolError.missingTitle
      }
      return .create(
        ReminderDraft(
          title: title,
          notes: arguments.notes,
          dueDate: try RemindersToolDateFormatter.optionalDate(from: arguments.dueDate),
          priority: try priority(from: arguments.priority) ?? .none,
          listName: arguments.listName
        )
      )
    case "complete":
      return .complete(id: try reminderID(from: arguments))
    case "update":
      guard
        arguments.title != nil || arguments.notes != nil || arguments.dueDate != nil
          || arguments.priority != nil
      else {
        throw RemindersToolError.noChanges
      }
      let clearDueDate = arguments.dueDate?.lowercased() == "none"
      let dueDate =
        clearDueDate
        ? nil
        : try RemindersToolDateFormatter.optionalDate(from: arguments.dueDate)
      return .update(
        id: try reminderID(from: arguments),
        changes: ReminderChanges(
          title: arguments.title,
          notes: arguments.notes,
          dueDate: dueDate,
          clearDueDate: clearDueDate,
          priority: try priority(from: arguments.priority)
        )
      )
    case "delete":
      return .delete(id: try reminderID(from: arguments))
    default:
      throw RemindersToolError.invalidMutationAction
    }
  }

  private func reminderID(from arguments: Arguments) throws -> String {
    guard let reminderID = arguments.reminderId, !reminderID.isEmpty else {
      throw RemindersToolError.missingReminderID
    }
    return reminderID
  }

  private func priority(from value: String?) throws -> ReminderPriority? {
    guard let value else { return nil }
    guard let priority = ReminderPriority(rawValue: value.lowercased()) else {
      throw RemindersToolError.invalidPriority
    }
    return priority
  }

  private func mutationRequest(for mutation: PreparedMutation) -> ToolMutationRequest {
    switch mutation {
    case .create(let draft):
      ToolMutationRequest(
        toolName: name,
        action: "create",
        summary: "Create reminder '\(draft.title)'",
        details: mutationDetails(for: draft)
      )
    case .complete(let id):
      ToolMutationRequest(
        toolName: name,
        action: "complete",
        summary: "Mark reminder '\(id)' complete",
        resourceID: id
      )
    case .update(let id, let changes):
      ToolMutationRequest(
        toolName: name,
        action: "update",
        summary: "Update reminder '\(changes.title ?? id)'",
        details: mutationDetails(for: changes),
        resourceID: id
      )
    case .delete(let id):
      ToolMutationRequest(
        toolName: name,
        action: "delete",
        summary: "Delete reminder '\(id)'",
        resourceID: id,
        isDestructive: true
      )
    }
  }

  private func mutationDetails(for draft: ReminderDraft) -> [ToolMutationDetail] {
    [
      ToolMutationDetail(label: "Title", value: draft.title),
      optionalDetail(label: "Notes", value: draft.notes),
      draft.dueDate.map {
        ToolMutationDetail(label: "Due", value: RemindersToolDateFormatter.string(from: $0))
      },
      ToolMutationDetail(label: "Priority", value: draft.priority.rawValue),
      optionalDetail(label: "List", value: draft.listName)
    ].compactMap { $0 }
  }

  private func mutationDetails(for changes: ReminderChanges) -> [ToolMutationDetail] {
    [
      optionalDetail(label: "Title", value: changes.title),
      optionalDetail(label: "Notes", value: changes.notes),
      changes.clearDueDate
        ? ToolMutationDetail(label: "Due", value: "none")
        : changes.dueDate.map {
          ToolMutationDetail(label: "Due", value: RemindersToolDateFormatter.string(from: $0))
        },
      changes.priority.map {
        ToolMutationDetail(label: "Priority", value: $0.rawValue)
      }
    ].compactMap { $0 }
  }

  private func optionalDetail(label: String, value: String?) -> ToolMutationDetail? {
    value.map { ToolMutationDetail(label: label, value: $0) }
  }

  private static func successMessage(for action: String) -> String {
    switch action {
    case "create": "Reminder created successfully"
    case "complete": "Reminder completed successfully"
    case "update": "Reminder updated successfully"
    case "delete": "Reminder deleted successfully"
    default: "Reminder mutation committed successfully"
    }
  }
}

/// Backward-compatible combined Reminders tool. New code should register split tools.
@available(
  *,
  deprecated,
  message:
    "Use RemindersReadTool and RemindersMutationTool so mutations require explicit confirmation."
)
public struct RemindersTool: Tool {
  public let name = "manageReminders"
  public let description = "Read reminders; mutations require host-app confirmation"

  @Generable
  public struct Arguments: RuntimeCompatibleGenerable {
    @Guide(description: "The action: 'create', 'query', 'complete', 'update', or 'delete'")
    public var action: String
    @Guide(description: "Reminder title") public var title: String?
    @Guide(description: "Reminder notes") public var notes: String?
    @Guide(description: "Due date") public var dueDate: String?
    @Guide(description: "Priority") public var priority: String?
    @Guide(description: "List name") public var listName: String?
    @Guide(description: "Reminder identifier") public var reminderId: String?
    @Guide(description: "Query filter") public var filter: String?

    public init(
      action: String = "",
      title: String? = nil,
      notes: String? = nil,
      dueDate: String? = nil,
      priority: String? = nil,
      listName: String? = nil,
      reminderId: String? = nil,
      filter: String? = nil
    ) {
      self.action = action
      self.title = title
      self.notes = notes
      self.dueDate = dueDate
      self.priority = priority
      self.listName = listName
      self.reminderId = reminderId
      self.filter = filter
    }
  }

  private let readTool: RemindersReadTool
  private let mutationTool: RemindersMutationTool?

  public init() {
    let service = EventKitRemindersService()
    self.readTool = RemindersReadTool(service: service)
    self.mutationTool = nil
  }

  public init(
    readService: any RemindersReading,
    mutationService: any RemindersMutating,
    confirmation: any ToolMutationConfirming
  ) {
    self.readTool = RemindersReadTool(service: readService)
    self.mutationTool = RemindersMutationTool(
      service: mutationService,
      confirmation: confirmation
    )
  }

  public init(confirmation: any ToolMutationConfirming) {
    let service = EventKitRemindersService()
    self.init(
      readService: service,
      mutationService: service,
      confirmation: confirmation
    )
  }

  public func call(arguments: Arguments) async throws -> some PromptRepresentable {
    switch arguments.action.lowercased() {
    case "query":
      return try await readTool.call(
        arguments: RemindersReadTool.Arguments(filter: arguments.filter))
    case "create", "complete", "update", "delete":
      guard let mutationTool else {
        throw ToolMutationExecutionError.confirmationRequired(
          for: ToolMutationRequest(
            toolName: "mutateReminders",
            action: arguments.action.lowercased(),
            summary: "Reminders mutation requested by deprecated RemindersTool",
            resourceID: arguments.reminderId,
            isDestructive: arguments.action.lowercased() == "delete"
          )
        )
      }
      return try await mutationTool.call(
        arguments: RemindersMutationTool.Arguments(
          action: arguments.action,
          title: arguments.title,
          notes: arguments.notes,
          dueDate: arguments.dueDate,
          priority: arguments.priority,
          listName: arguments.listName,
          reminderId: arguments.reminderId
        )
      )
    default:
      throw RemindersToolError.invalidAction
    }
  }

  static func formatReminderQueryResults(_ reminders: [ReminderRecord]) -> String {
    RemindersReadTool.formatReminderQueryResults(reminders)
  }
}

public enum RemindersToolError: Error, LocalizedError, Sendable {
  case accessDenied
  case invalidAction
  case invalidMutationAction
  case invalidPriority
  case invalidDueDate
  case noChanges
  case missingTitle
  case missingReminderID
  case reminderNotFound

  public var errorDescription: String? {
    switch self {
    case .accessDenied:
      "Access to Reminders was denied. Grant permission in Settings."
    case .invalidAction:
      "Invalid action. Use 'create', 'query', 'complete', 'update', or 'delete'."
    case .invalidMutationAction:
      "Invalid mutation action. Use 'create', 'complete', 'update', or 'delete'."
    case .invalidPriority:
      "Invalid priority. Use 'none', 'low', 'medium', or 'high'."
    case .invalidDueDate:
      "Invalid due date. Use YYYY-MM-DD HH:mm:ss or an ISO 8601 date."
    case .noChanges:
      "At least one reminder field is required for an update."
    case .missingTitle:
      "Title is required to create a reminder."
    case .missingReminderID:
      "Reminder ID is required."
    case .reminderNotFound:
      "Reminder not found with the provided ID."
    }
  }
}

private enum RemindersToolDateFormatter {
  static func optionalDate(from value: String?) throws -> Date? {
    guard let value else { return nil }
    if value.lowercased() == "none" {
      return nil
    }
    guard let date = date(from: value) else {
      throw RemindersToolError.invalidDueDate
    }
    return date
  }

  static func date(from value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.timeZone = .current

    for format in [
      "yyyy-MM-dd HH:mm:ss",
      "yyyy-MM-dd HH:mm",
      "yyyy-MM-dd",
      "MM/dd/yyyy HH:mm:ss",
      "MM/dd/yyyy HH:mm",
      "MM/dd/yyyy"
    ] {
      formatter.dateFormat = format
      if let date = formatter.date(from: value) {
        return date
      }
    }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.timeZone = .current
    return isoFormatter.date(from: value)
  }

  static func string(from date: Date?) -> String {
    guard let date else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = .current
    return formatter.string(from: date)
  }
}

typealias ReminderSnapshot = ReminderRecord
typealias RemindersError = RemindersToolError
