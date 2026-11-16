import Darwin
import Foundation

/// One line of a run's `driver.jsonl`: what the driver did and saw, on the same uptime clock as the
/// app's telemetry. Nothing reads it back, so it only encodes.
public struct DriverEvent: Encodable, Equatable, Sendable {
  public enum Kind: String, Encodable, Sendable {
    case idle
    case discover
    case resolve
    case skip
    case fail
    case mouseRecovery = "mouse-recovery"
  }

  public var uptime: TimeInterval
  public var event: Kind
  public var action: Int?
  public var control: String?
  public var step: ResolutionStep?
  public var attempts: Int?
  public var waitedMs: Double?
  public var timedOut: Bool?
  public var pendingWork: Int?
  public var openWork: [String: Int]?
  public var windows: Int?
  public var scope: WindowScopeSource?
  public var elements: Int?
  public var elapsedMs: Double?
  public var skipped: Bool?
  /// Role of the window that has focus, on `discover` events; nil when no window has focus.
  public var focusedRole: String?
  public var focusedSubrole: String?
  public var focusLocation: FocusLocation?
  /// The overlay whose subtree discovery offered, and its depth below the application element.
  public var modalRole: String?
  public var modalDepth: Int?
  /// True when an overlay had focus but could not be located, so discovery offered only plain keys.
  public var unlocated: Bool?
  public var context: String?
  public var hitProcess: Int32?
  public var hitBundleIdentifier: String?
  public var recovered: Bool?

  public init(
    uptime: TimeInterval, event: Kind, action: Int? = nil, control: String? = nil,
    step: ResolutionStep? = nil, attempts: Int? = nil, waitedMs: Double? = nil,
    timedOut: Bool? = nil, pendingWork: Int? = nil, openWork: [String: Int]? = nil,
    windows: Int? = nil, scope: WindowScopeSource? = nil, elements: Int? = nil,
    elapsedMs: Double? = nil, skipped: Bool? = nil, focusedRole: String? = nil,
    focusedSubrole: String? = nil, focusLocation: FocusLocation? = nil,
    modalRole: String? = nil, modalDepth: Int? = nil, unlocated: Bool? = nil,
    context: String? = nil, hitProcess: Int32? = nil, hitBundleIdentifier: String? = nil,
    recovered: Bool? = nil
  ) {
    self.uptime = uptime
    self.event = event
    self.action = action
    self.control = control
    self.step = step
    self.attempts = attempts
    self.waitedMs = waitedMs
    self.timedOut = timedOut
    self.pendingWork = pendingWork
    self.openWork = openWork
    self.windows = windows
    self.scope = scope
    self.elements = elements
    self.elapsedMs = elapsedMs
    self.skipped = skipped
    self.focusedRole = focusedRole
    self.focusedSubrole = focusedSubrole
    self.focusLocation = focusLocation
    self.modalRole = modalRole
    self.modalDepth = modalDepth
    self.unlocated = unlocated
    self.context = context
    self.hitProcess = hitProcess
    self.hitBundleIdentifier = hitBundleIdentifier
    self.recovered = recovered
  }

  /// A skipped wait read no telemetry, so it carries none of the wait's figures.
  public static func idle(_ wait: IdleWaitResult, uptime: TimeInterval, action: Int)
    -> DriverEvent
  {
    if wait.skipped {
      return DriverEvent(uptime: uptime, event: .idle, action: action, skipped: true)
    }
    return DriverEvent(
      uptime: uptime, event: .idle, action: action, waitedMs: wait.seconds * 1000,
      timedOut: wait.timedOut, pendingWork: wait.openWork.values.reduce(0, +),
      openWork: wait.openWork)
  }
}

public enum DriverLog {
  public static func line(_ event: DriverEvent) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(event), as: UTF8.self)
  }

  public static func open(_ url: URL) throws -> FileHandle {
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: url)
    }
    let handle = try FileHandle(forWritingTo: url)
    precondition(fcntl(handle.fileDescriptor, F_SETFL, O_APPEND) == 0)
    return handle
  }

  public static func append(_ event: DriverEvent, to handle: FileHandle) throws {
    let text = try line(event) + "\n"
    try handle.write(contentsOf: Data(text.utf8))
  }
}
