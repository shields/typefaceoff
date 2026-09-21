import Foundation

public struct FuzzTrace: Codable, Equatable, Sendable {
  public static let schemaVersion = 1

  public var version: Int
  public var seed: UInt64
  public var actions: [FuzzAction]
  public var origin: String

  public init(seed: UInt64, actions: [FuzzAction] = [], origin: String = "generated") {
    version = Self.schemaVersion
    self.seed = seed
    self.actions = actions
    self.origin = origin
  }
}

public struct FuzzAction: Codable, Equatable, Hashable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case press
    case setValue
    case increment
    case decrement
    case shortcut
    case key
    case scroll
    case pause
    case selectFont
    case click
    case drag
    case showMenu
  }

  public var kind: Kind
  public var target: String?
  public var targetPath: [Int]?
  public var targetRole: String?
  public var commitValue: Bool?
  public var value: String?
  public var keyCode: UInt16?
  public var modifiers: UInt64?
  public var deltaX: Double?
  public var deltaY: Double?
  public var delayMilliseconds: Int

  public init(
    kind: Kind, target: String? = nil, value: String? = nil, keyCode: UInt16? = nil,
    modifiers: UInt64? = nil, deltaX: Double? = nil, deltaY: Double? = nil,
    delayMilliseconds: Int = 30, targetPath: [Int]? = nil, targetRole: String? = nil,
    commitValue: Bool? = nil
  ) {
    self.kind = kind
    self.target = target
    self.targetPath = targetPath
    self.targetRole = targetRole
    self.commitValue = commitValue
    self.value = value
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.deltaX = deltaX
    self.deltaY = deltaY
    self.delayMilliseconds = delayMilliseconds
  }
}

public struct ExecutionFinding: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case crash
    case hang
    case correctness
    case slow
    case automation
    case unavailable
  }

  public var kind: Kind
  public var signature: String
  public var detail: String

  public init(kind: Kind, signature: String, detail: String) {
    self.kind = kind
    self.signature = signature
    self.detail = detail
  }
}

public struct ExecutionReport: Codable, Equatable, Sendable {
  public var trace: FuzzTrace
  public var startedAt: Date
  public var durationMilliseconds: Double
  public var workloadDurationMilliseconds: Double?
  public var actionMilliseconds: [Double]
  public var coverage: Set<String>
  public var countBuckets: Set<String>
  public var findings: [ExecutionFinding]
  public var exitStatus: Int32?
  public var terminatedByWatchdog: Bool
  public var metadata: [String: String]

  public var pacingMilliseconds: Double {
    Double(trace.actions.map(\.delayMilliseconds).reduce(0, +))
  }

  public var measuredMilliseconds: Double {
    max(0, (workloadDurationMilliseconds ?? durationMilliseconds) - pacingMilliseconds)
  }

  /// An unavailable desktop must not hide a crash, hang, or invariant failure.
  public var needsAvailabilityRecovery: Bool {
    findings.contains { $0.kind == .unavailable }
      && findings.allSatisfy { $0.kind == .unavailable || $0.kind == .automation }
  }

  public var isBenchmarkSample: Bool {
    findings.isEmpty && workloadDurationMilliseconds != nil
      && actionMilliseconds.count == trace.actions.count
  }

  public init(
    trace: FuzzTrace, startedAt: Date, durationMilliseconds: Double,
    workloadDurationMilliseconds: Double? = nil,
    actionMilliseconds: [Double], coverage: Set<String> = [], countBuckets: Set<String> = [],
    findings: [ExecutionFinding] = [], exitStatus: Int32? = nil,
    terminatedByWatchdog: Bool = false, metadata: [String: String] = [:]
  ) {
    self.trace = trace
    self.startedAt = startedAt
    self.durationMilliseconds = durationMilliseconds
    self.workloadDurationMilliseconds = workloadDurationMilliseconds
    self.actionMilliseconds = actionMilliseconds
    self.coverage = coverage
    self.countBuckets = countBuckets
    self.findings = findings
    self.exitStatus = exitStatus
    self.terminatedByWatchdog = terminatedByWatchdog
    self.metadata = metadata
  }
}

public enum TraceIO {
  public static func load(_ url: URL) throws -> FuzzTrace {
    let trace = try JSONDecoder().decode(FuzzTrace.self, from: Data(contentsOf: url))
    guard trace.version == FuzzTrace.schemaVersion else {
      throw TraceError.unsupportedVersion(trace.version)
    }
    return trace
  }

  public static func save(_ trace: FuzzTrace, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(trace).write(to: url, options: .atomic)
  }

  public static func save(_ report: ExecutionReport, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: url, options: .atomic)
  }

  public enum TraceError: Error, Equatable {
    case unsupportedVersion(Int)
  }
}
