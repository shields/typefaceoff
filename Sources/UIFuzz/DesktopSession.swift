import ApplicationServices
import CoreGraphics
import UIFuzzSupport

struct DesktopSession {
  let onConsole: Bool
  let loggedIn: Bool
  let accessibility: Bool
  let eventPosting: Bool

  static func current() -> DesktopSession {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    return DesktopSession(
      onConsole: session[kCGSessionOnConsoleKey as String] as? Bool == true,
      loggedIn: session[kCGSessionLoginDoneKey as String] as? Bool == true,
      accessibility: AXIsProcessTrusted(), eventPosting: CGPreflightPostEventAccess())
  }

  var unavailableReason: String? {
    if !onConsole || !loggedIn { return "The driver's user session is not on the active console." }
    if !accessibility || !eventPosting {
      return "The driver needs Accessibility and event-posting permission."
    }
    return nil
  }

  var metadata: [String: String] {
    [
      "session-on-console": String(onConsole), "session-logged-in": String(loggedIn),
      "accessibility-permitted": String(accessibility),
      "event-posting-permitted": String(eventPosting),
    ]
  }

  func requireAvailable() throws {
    if let unavailableReason {
      throw AvailabilityError(signature: "desktop-session", detail: unavailableReason)
    }
  }
}

struct AvailabilityError: Error, CustomStringConvertible {
  let signature: String
  let detail: String

  var description: String { detail }
  var finding: ExecutionFinding {
    ExecutionFinding(kind: .unavailable, signature: signature, detail: detail)
  }
}
