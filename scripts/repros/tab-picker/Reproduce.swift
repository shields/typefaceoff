import AppKit
import ApplicationServices
import Darwin
import Foundation

struct ReproFailure: Error, CustomStringConvertible {
  let description: String
  let accessibilityError: AXError?

  init(description: String, accessibilityError: AXError? = nil) {
    self.description = description
    self.accessibilityError = accessibilityError
  }
}

func read(_ node: AXUIElement, _ name: String) throws -> CFTypeRef? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(node, name as CFString, &value)
  switch result {
  case .success: return value
  case .noValue, .attributeUnsupported: return nil
  default:
    throw ReproFailure(
      description: "Reading \(name) returned \(result.rawValue)", accessibilityError: result)
  }
}

func find(_ root: AXUIElement, named name: String, depth: Int = 0) throws -> AXUIElement? {
  for attribute in [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
    if try read(root, attribute) as? String == name { return root }
  }
  guard depth < 10 else { return nil }
  let children: [AXUIElement]
  do {
    children = try read(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
  } catch let error as ReproFailure where error.accessibilityError == .failure {
    return nil
  }
  for child in children {
    if let found = try find(child, named: name, depth: depth + 1) { return found }
  }
  return nil
}

func waitFor(_ name: String, in root: AXUIElement) throws -> AXUIElement {
  print("Waiting for \(name)")
  let deadline = ProcessInfo.processInfo.systemUptime + 5
  while ProcessInfo.processInfo.systemUptime < deadline {
    do {
      if let found = try find(root, named: name) { return found }
    } catch let error as ReproFailure where error.accessibilityError == .cannotComplete {
      if ProcessInfo.processInfo.systemUptime >= deadline { throw error }
    }
    Thread.sleep(forTimeInterval: 0.05)
  }
  throw ReproFailure(description: "Timed out waiting for \(name)")
}

func center(_ node: AXUIElement) throws -> CGPoint {
  guard let rawPosition = try read(node, kAXPositionAttribute),
    let rawSize = try read(node, kAXSizeAttribute)
  else { throw ReproFailure(description: "The control has no frame") }
  var position = CGPoint.zero
  var size = CGSize.zero
  precondition(AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position))
  precondition(AXValueGetValue(rawSize as! AXValue, .cgSize, &size))
  return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
}

func mouse(_ type: CGEventType, at point: CGPoint) {
  let event = CGEvent(
    mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
  event.post(tap: .cgSessionEventTap)
}

@main
struct Reproduce {
  static func main() {
    do {
      try run()
    } catch {
      FileHandle.standardError.write(Data("\(error)\n".utf8))
      exit(1)
    }
  }

  static func run() throws {
    guard CommandLine.arguments.count >= 2 else {
      throw ReproFailure(description: "Usage: reproduce APP_EXECUTABLE [--native-appearance]")
    }
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
      throw ReproFailure(description: "Accessibility and event-posting permissions are required")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
    process.arguments = Array(CommandLine.arguments.dropFirst(2))
    try process.run()
    defer {
      if process.isRunning { process.terminate() }
      process.waitUntilExit()
    }
    let app = AXUIElementCreateApplication(process.processIdentifier)
    _ = try waitFor("Size", in: app)
    precondition(NSRunningApplication(processIdentifier: process.processIdentifier)!.activate())
    Thread.sleep(forTimeInterval: 0.3)
    let view = try waitFor("View", in: app)
    precondition(AXUIElementPerformAction(view, kAXPressAction as CFString) == .success)
    let overview = try waitFor("toggleTabOverview:", in: app)
    let point = try center(overview)
    mouse(.leftMouseDown, at: point)
    mouse(.leftMouseUp, at: point)
    let newTab = try waitFor("New Tab", in: app)
    let newPoint = try center(newTab)
    mouse(.leftMouseDown, at: newPoint)
    mouse(.leftMouseUp, at: newPoint)
    Thread.sleep(forTimeInterval: 0.3)
    let slider = try waitFor("Size", in: app)
    let start = try center(slider)
    let end = CGPoint(x: start.x + 14, y: start.y - 52)
    mouse(.leftMouseDown, at: start)
    mouse(.leftMouseDragged, at: end)
    mouse(.leftMouseUp, at: end)
    Thread.sleep(forTimeInterval: 0.4)
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)!
      event.postToPid(process.processIdentifier)
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    guard !process.isRunning else {
      throw ReproFailure(description: "The app did not crash")
    }
    guard process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGABRT else {
      throw ReproFailure(
        description:
          "The app exited for reason \(process.terminationReason.rawValue) with status \(process.terminationStatus)"
      )
    }
    print("The app crashed with SIGABRT as expected")
  }
}
