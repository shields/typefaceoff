import ApplicationServices
import Foundation

struct ReproFailure: Error, CustomStringConvertible {
  let description: String
}

func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
  switch result {
  case .success: return value
  case .noValue, .attributeUnsupported: return nil
  default: throw ReproFailure(description: "Reading \(name) returned \(result.rawValue)")
  }
}

func button(in element: AXUIElement, titled title: String, depth: Int = 0) throws -> AXUIElement? {
  if try attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
    try attribute(element, kAXTitleAttribute) as? String == title
  {
    return element
  }
  guard depth < 10 else { return nil }
  for child in try attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    if let found = try button(in: child, titled: title, depth: depth + 1) { return found }
  }
  return nil
}

func waitFor(_ description: String, _ probe: () throws -> AXUIElement?) throws -> AXUIElement {
  let deadline = ProcessInfo.processInfo.systemUptime + 12
  while ProcessInfo.processInfo.systemUptime < deadline {
    if let element = try probe() { return element }
    Thread.sleep(forTimeInterval: 0.05)
  }
  throw ReproFailure(description: "Timed out waiting for \(description)")
}

@main
struct Press {
  static func main() {
    do {
      try run()
    } catch {
      FileHandle.standardError.write(Data("\(error)\n".utf8))
      exit(1)
    }
  }

  static func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 2, ["label", "identifier", "none"].contains(arguments[1]) else {
      throw ReproFailure(description: "Usage: press APP_EXECUTABLE label|identifier|none")
    }
    guard AXIsProcessTrusted() else {
      throw ReproFailure(
        description: "Enable Accessibility permission for this terminal, then retry.")
    }
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    guard let session, session["CGSSessionScreenIsLocked"] as? Bool != true else {
      throw ReproFailure(description: "An unlocked desktop session is required.")
    }
    let mode = arguments[1]
    let process = Process()
    process.executableURL = URL(fileURLWithPath: arguments[0])
    process.arguments =
      mode == "none" ? ["--without-setter"] : (mode == "identifier" ? ["--identifier"] : [])
    try process.run()
    defer {
      if process.isRunning { process.terminate() }
      process.waitUntilExit()
    }
    let app = AXUIElementCreateApplication(process.processIdentifier)
    let window = try waitFor("main window") {
      var raw: CFTypeRef?
      let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
      if result == .cannotComplete { return nil }
      guard result == .success else {
        throw ReproFailure(description: "Reading AXWindows returned \(result.rawValue)")
      }
      for window in raw as? [AXUIElement] ?? [] {
        if try attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole {
          return window
        }
      }
      return nil
    }
    var failures = 0
    for index in 1...10 {
      let open = try waitFor("Open sheet") { try button(in: window, titled: "Open sheet") }
      guard try attribute(open, kAXEnabledAttribute) as? Bool == true else {
        throw ReproFailure(description: "Open sheet is disabled.")
      }
      let result = AXUIElementPerformAction(open, kAXPressAction as CFString)
      let cancel = try waitFor("Cancel in the sheet") { try button(in: window, titled: "Cancel") }
      print("mode=\(mode) press=\(index) enabled=true AXPress=\(result.rawValue) sheetOpened=true")
      if result != .success { failures += 1 }
      let dismissed = AXUIElementPerformAction(cancel, kAXPressAction as CFString)
      guard dismissed == .success else {
        throw ReproFailure(description: "Pressing Cancel returned \(dismissed.rawValue)")
      }
      _ = try waitFor("sheet dismissal") {
        try button(in: window, titled: "Cancel") == nil ? window : nil
      }
      Thread.sleep(forTimeInterval: 0.3)
    }
    print("SUMMARY mode=\(mode) presses=10 failures=\(failures) sheetsOpened=10")
  }
}
