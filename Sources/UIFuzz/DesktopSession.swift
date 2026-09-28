import ApplicationServices
import CoreGraphics
import UIFuzzSupport

struct DesktopSession {
  static let unavailableSignature = "desktop-session"

  let onConsole: Bool
  let loggedIn: Bool
  let screenLocked: Bool
  let accessibility: Bool
  let eventPosting: Bool

  static func current() -> DesktopSession {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    return DesktopSession(
      onConsole: session[kCGSessionOnConsoleKey as String] as? Bool == true,
      loggedIn: session[kCGSessionLoginDoneKey as String] as? Bool == true,
      // Undocumented; present only while the screen is locked.
      screenLocked: session["CGSSessionScreenIsLocked"] as? Bool == true,
      accessibility: AXIsProcessTrusted(), eventPosting: CGPreflightPostEventAccess())
  }

  var unavailableReason: String? {
    if !onConsole || !loggedIn { return "The driver's user session is not on the active console." }
    if screenLocked {
      return "The screen is locked, which hides the app's windows from Accessibility."
    }
    if !accessibility || !eventPosting {
      return "The driver needs Accessibility and event-posting permission."
    }
    return nil
  }

  var metadata: [String: String] {
    [
      "session-on-console": String(onConsole), "session-logged-in": String(loggedIn),
      "session-screen-locked": String(screenLocked),
      "accessibility-permitted": String(accessibility),
      "event-posting-permitted": String(eventPosting),
    ]
  }

  func requireAvailable() throws {
    if let unavailableReason {
      throw AvailabilityError(signature: Self.unavailableSignature, detail: unavailableReason)
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
