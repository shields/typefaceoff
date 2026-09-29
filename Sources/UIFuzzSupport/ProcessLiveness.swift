import Darwin
import Foundation

public enum ExitPhase: Sendable {
  case launch
  case beforeAction
  case duringAction
  case afterActions
}

public enum ProcessLiveness {
  public static let launchTerminationSignature = "launch-termination"

  // NSRunningApplication.isTerminated only changes when the main run loop turns, which the
  // driver never does after launch. EPERM means the process exists but belongs to someone else.
  public static func isAlive(_ pid: pid_t) -> Bool {
    pid > 0 && (kill(pid, 0) == 0 || errno != ESRCH)
  }

  public static func waitForExit(
    _ pid: pid_t, timeout: TimeInterval, pollInterval: TimeInterval = 0.01,
    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
    isAlive: (pid_t) -> Bool = ProcessLiveness.isAlive
  ) -> Bool {
    let deadline = clock() + timeout
    while isAlive(pid) {
      let remaining = deadline - clock()
      if remaining <= 0 { return false }
      sleep(min(pollInterval, remaining))
    }
    return true
  }

  public static func unexpectedExitFinding(
    phase: ExitPhase, actionsDispatched: Int, lastAction: String?,
    secondsSinceLastAction: TimeInterval?, secondsSinceHeartbeat: TimeInterval?,
    note: String? = nil
  ) -> ExecutionFinding {
    var detail: String
    switch phase {
    case .launch:
      detail = "The app exited during launch, before any action was dispatched."
    case .beforeAction:
      detail =
        "The app exited before action \(actionsDispatched + 1) was dispatched, after \(actionsDispatched) actions."
    case .duringAction:
      detail = "The app exited while the driver was performing an action."
    case .afterActions:
      detail =
        "The app exited after \(actionsDispatched) dispatched actions, before the driver requested termination."
    }
    if let lastAction, let secondsSinceLastAction {
      detail +=
        " Action \(actionsDispatched) (\(lastAction)) started \(seconds(secondsSinceLastAction)) before the exit was noticed."
    }
    if let secondsSinceHeartbeat {
      detail += " The last main-thread heartbeat was \(seconds(secondsSinceHeartbeat)) earlier."
    } else {
      detail += " The app never emitted a main-thread heartbeat."
    }
    if let note { detail += " \(note)" }
    return ExecutionFinding(
      kind: .crash,
      signature: phase == .launch ? launchTerminationSignature : "unexpected-termination",
      detail: detail)
  }

  private static func seconds(_ value: TimeInterval) -> String {
    String(format: "%.2f s", value)
  }
}
