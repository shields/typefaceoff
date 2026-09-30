import Foundation

public protocol ResolutionClock {
  var now: TimeInterval { get }
  func sleep(_ seconds: TimeInterval)
}

public struct ResolutionRetry: Equatable, Sendable {
  public var timeoutSeconds: TimeInterval
  public var maximumAttempts: Int

  public static let recorded = ResolutionRetry(timeoutSeconds: 2.0, maximumAttempts: .max)
  public static let live = ResolutionRetry(timeoutSeconds: 0.5, maximumAttempts: 3)
  public static let reveal = ResolutionRetry(timeoutSeconds: 1.0, maximumAttempts: .max)
  /// A single attempt with no waiting, for readiness polls that have their own loop.
  public static let once = ResolutionRetry(timeoutSeconds: 0.001, maximumAttempts: 1)

  public static let idleInterval: TimeInterval = 0.1
  public static let busyInterval: TimeInterval = 0.25
  public static let wakeInterval: TimeInterval = 0.05

  public init(timeoutSeconds: TimeInterval, maximumAttempts: Int) {
    precondition(timeoutSeconds > 0 && maximumAttempts > 0)
    self.timeoutSeconds = timeoutSeconds
    self.maximumAttempts = maximumAttempts
  }

  /// Attempts on a fresh capture until one finds the control, the attempts run out, or the
  /// deadline passes; a final attempt always runs at the deadline. `idle` receives the time of the
  /// attempt that just failed and must not touch the accessibility tree.
  public func run<Node: AccessibilityNode>(
    clock: some ResolutionClock, idle: (_ since: TimeInterval) -> Bool,
    checkpoint: () throws -> Void, attempt: () -> Resolution<Node>
  ) throws -> (Resolution<Node>, attempts: Int) {
    let deadline = clock.now + timeoutSeconds
    var attempts = 0
    var result: Resolution<Node>
    var finished = false
    repeat {
      try checkpoint()
      let attemptedAt = clock.now
      attempts += 1
      result = attempt()
      finished = result.node != nil || attempts >= maximumAttempts || clock.now >= deadline
      if !finished {
        let interval = idle(attemptedAt) ? Self.idleInterval : Self.busyInterval
        let wakeAt = min(attemptedAt + interval, deadline)
        while clock.now < wakeAt {
          clock.sleep(min(Self.wakeInterval, wakeAt - clock.now))
        }
      }
    } while !finished
    return (result, attempts)
  }
}
