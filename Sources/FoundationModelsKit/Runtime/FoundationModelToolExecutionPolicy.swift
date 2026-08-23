import Foundation

/// JSON values supplied by a model when it invokes a tool.
public enum FoundationModelToolValue: Codable, Equatable, Hashable, Sendable {
  case object([String: FoundationModelToolValue])
  case array([FoundationModelToolValue])
  case string(String)
  case number(Double)
  case boolean(Bool)
  case null

  public init(from decoder: Decoder) throws {
    if let c = try? decoder.singleValueContainer(), c.decodeNil() { self = .null; return }
    if let c = try? decoder.singleValueContainer(), let b = try? c.decode(Bool.self) { self = .boolean(b); return }
    if let c = try? decoder.singleValueContainer(), let n = try? c.decode(Double.self) { self = .number(n); return }
    if let c = try? decoder.singleValueContainer(), let s = try? c.decode(String.self) { self = .string(s); return }
    if var c = try? decoder.unkeyedContainer() {
      var values: [FoundationModelToolValue] = []
      while !c.isAtEnd { values.append(try c.decode(Self.self)) }
      self = .array(values); return
    }
    let c = try decoder.container(keyedBy: AnyCodingKey.self)
    var values: [String: FoundationModelToolValue] = [:]
    for key in c.allKeys { values[key.stringValue] = try c.decode(Self.self, forKey: key) }
    self = .object(values)
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .null: var c = encoder.singleValueContainer(); try c.encodeNil()
    case .boolean(let v): var c = encoder.singleValueContainer(); try c.encode(v)
    case .number(let v): var c = encoder.singleValueContainer(); try c.encode(v)
    case .string(let v): var c = encoder.singleValueContainer(); try c.encode(v)
    case .array(let v): var c = encoder.unkeyedContainer(); for value in v { try c.encode(value) }
    case .object(let v): try v.encode(to: encoder)
    }
  }
  private struct AnyCodingKey: CodingKey { let stringValue: String; let intValue: Int?; init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }; init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue } }
}

/// A provider-neutral validation schema for model-authored tool arguments.
public final class FoundationModelToolSchema: Codable, Sendable, Equatable {
  public let type: String?
  public let properties: [String: FoundationModelToolSchema]?
  public let required: [String]
  public let enumValues: [FoundationModelToolValue]?
  public let anyOf: [FoundationModelToolSchema]?
  public let minimum: Double?
  public let maximum: Double?
  public let items: FoundationModelToolSchema?
  public let additionalProperties: Bool
  public init(type: String? = nil, properties: [String: FoundationModelToolSchema]? = nil, required: [String] = [], enumValues: [FoundationModelToolValue]? = nil, anyOf: [FoundationModelToolSchema]? = nil, minimum: Double? = nil, maximum: Double? = nil, items: FoundationModelToolSchema? = nil, additionalProperties: Bool = false) { self.type = type; self.properties = properties; self.required = required; self.enumValues = enumValues; self.anyOf = anyOf; self.minimum = minimum; self.maximum = maximum; self.items = items; self.additionalProperties = additionalProperties }
  public static func == (lhs: FoundationModelToolSchema, rhs: FoundationModelToolSchema) -> Bool { lhs.type == rhs.type && lhs.properties == rhs.properties && lhs.required == rhs.required && lhs.enumValues == rhs.enumValues && lhs.anyOf == rhs.anyOf && lhs.minimum == rhs.minimum && lhs.maximum == rhs.maximum && lhs.items == rhs.items && lhs.additionalProperties == rhs.additionalProperties }
}

public enum FoundationModelToolExecutionFailure: Error, Equatable, Sendable {
  case invalidArguments(path: String, reason: String)
  case loopDetected(tool: String)
  case budgetExceeded(String)
  case confirmationRequired(tool: String)
}

public struct FoundationModelToolExecutionBudget: Sendable, Equatable {
  public var maxCalls: Int; public var maxRepairs: Int; public var maxDuration: Duration?; public var maxOutputTokens: Int?
  public init(maxCalls: Int = 16, maxRepairs: Int = 2, maxDuration: Duration? = nil, maxOutputTokens: Int? = nil) { self.maxCalls = maxCalls; self.maxRepairs = maxRepairs; self.maxDuration = maxDuration; self.maxOutputTokens = maxOutputTokens }
}

public enum FoundationModelToolSideEffect: Sendable, Equatable {
  case none
  case confirmation
  case idempotency(key: String)
}

public protocol FoundationModelToolExecutionConfirming: Sendable { func confirm(tool: String, arguments: FoundationModelToolValue) async -> Bool }

/// Validates and supervises tool calls independently of the model provider.
public actor FoundationModelToolExecutionPolicy {
  private let budget: FoundationModelToolExecutionBudget
  private var calls = 0; private var repairs = 0; private var seen = Set<String>(); private let clock = ContinuousClock(); private let started = ContinuousClock.Instant.now
  public init(budget: FoundationModelToolExecutionBudget = .init()) { self.budget = budget }
  public func recordRepair() throws { guard repairs < budget.maxRepairs else { throw FoundationModelToolExecutionFailure.budgetExceeded("repair limit") }; repairs += 1 }
  public func execute<T: Sendable>(tool: String, arguments: FoundationModelToolValue, schema: FoundationModelToolSchema, sideEffect: FoundationModelToolSideEffect = .none, confirmer: (any FoundationModelToolExecutionConfirming)? = nil, outputTokenEstimator: @escaping @Sendable (T) -> Int = { _ in 0 }, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    guard calls < budget.maxCalls else { throw FoundationModelToolExecutionFailure.budgetExceeded("call limit") }
    if let limit = budget.maxDuration, clock.now - started > limit { throw FoundationModelToolExecutionFailure.budgetExceeded("duration limit") }
    try validate(arguments, against: schema, path: "$")
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let key = try String(data: encoder.encode(arguments), encoding: .utf8) ?? ""
    guard seen.insert(tool + "\0" + key).inserted else { throw FoundationModelToolExecutionFailure.loopDetected(tool: tool) }
    if case .confirmation = sideEffect { guard let confirmer, await confirmer.confirm(tool: tool, arguments: arguments) else { throw FoundationModelToolExecutionFailure.confirmationRequired(tool: tool) } }
    calls += 1
    try Task.checkCancellation(); let output = try await operation(); try Task.checkCancellation()
    if let limit = budget.maxOutputTokens, outputTokenEstimator(output) > limit { throw FoundationModelToolExecutionFailure.budgetExceeded("output-token limit") }
    return output
  }
  private func validate(_ value: FoundationModelToolValue, against schema: FoundationModelToolSchema, path: String) throws {
    if let branches = schema.anyOf {
      let matches = branches.contains { (try? validate(value, against: $0, path: path)) == nil }
      if !matches { throw FoundationModelToolExecutionFailure.invalidArguments(path: path, reason: "does not match any schema branch") }
    }
    if let e = schema.enumValues, !e.contains(value) { throw FoundationModelToolExecutionFailure.invalidArguments(path: path, reason: "not in enum") }
    switch (schema.type, value) {
    case ("object", .object(let object)):
      for name in schema.required where object[name] == nil { throw FoundationModelToolExecutionFailure.invalidArguments(path: path, reason: "missing required property \(name)") }
      if !schema.additionalProperties, let properties = schema.properties { for name in object.keys where properties[name] == nil { throw FoundationModelToolExecutionFailure.invalidArguments(path: path, reason: "unknown property \(name)") } }
      for (name, child) in schema.properties ?? [:] where object[name] != nil { try validate(object[name]!, against: child, path: path + "." + name) }
    case ("array", .array(let values)): for (i, value) in values.enumerated() { if let items = schema.items { try validate(value, against: items, path: "\(path)[\(i)]") } }
    case ("string", .string), ("boolean", .boolean), ("number", .number): break
    case ("integer", .number(let number)) where number.rounded() == number: break
    case (nil, _): break
    default: throw FoundationModelToolExecutionFailure.invalidArguments(path: path, reason: "wrong type")
    }
    if case .number(let number) = value { if let min = schema.minimum, number < min { throw FoundationModelToolExecutionFailure.invalidArguments(path: path, reason: "below minimum") }; if let max = schema.maximum, number > max { throw FoundationModelToolExecutionFailure.invalidArguments(path: path, reason: "above maximum") } }
  }
}
