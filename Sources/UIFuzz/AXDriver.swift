import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import UIFuzzSupport

enum DriverError: Error, CustomStringConvertible {
  case applicationDidNotLaunch
  case controlMissing(String)
  case actionFailed(String, AXError)

  var description: String {
    switch self {
    case .applicationDidNotLaunch: "The app did not expose an accessibility window"
    case .controlMissing(let target): "Control not found: \(target)"
    case .actionFailed(let action, let error):
      "Accessibility action \(action) failed: \(error.rawValue)"
    }
  }
}

struct AXDriver {
  let processIdentifier: pid_t
  let application: AXUIElement

  init(processIdentifier: pid_t) throws {
    self.processIdentifier = processIdentifier
    application = AXUIElementCreateApplication(processIdentifier)
    AXUIElementSetMessagingTimeout(application, 0.5)
    var ready = false
    for _ in 0..<200 {
      if !ProcessLiveness.isAlive(processIdentifier) { break }
      try DesktopSession.current().requireAvailable()
      let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] ?? []
      if windows.contains(where: { stringAttribute(kAXRoleAttribute, of: $0) == kAXWindowRole }) {
        ready = true
        break
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    guard ready else {
      throw AvailabilityError(
        signature: "workbench", detail: DriverError.applicationDidNotLaunch.description)
    }
  }

  func waitForWorkbench() throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    repeat {
      try DesktopSession.current().requireAvailable()
      if hasWorkbenchControls { return }
      Thread.sleep(forTimeInterval: 0.05)
    } while ProcessInfo.processInfo.systemUptime < deadline
    throw AvailabilityError(
      signature: "workbench",
      detail: "The app's workbench controls are unavailable to Accessibility.")
  }

  var hasWorkbenchControls: Bool {
    let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] ?? []
    return windows.contains { window in
      firstDescendant(of: window) { names(of: $0).contains("Shared point size") } != nil
    }
  }

  static func waitForPermissions() {
    let waitingFor = ProcessInfo.processInfo.environment["TYPEFACEOFF_FUZZ_PERMISSION_STAGE"]
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    let accessibilityGranted =
      waitingFor == nil ? AXIsProcessTrustedWithOptions(options) : AXIsProcessTrusted()
    guard !accessibilityGranted else {
      if waitingFor == "accessibility" {
        announce("Accessibility permission granted; continuing.")
      }
      unsetenv("TYPEFACEOFF_FUZZ_PERMISSION_STAGE")
      waitForEventPostingPermission()
      return
    }

    if waitingFor != "accessibility" {
      announce(
        "Waiting for Accessibility permission. In System Settings > Privacy & Security > Accessibility, enable:\n\(permissionTarget())"
      )
    }
    restartAfterPermissionDelay(stage: "accessibility")
  }

  private static func waitForEventPostingPermission() {
    guard !CGPreflightPostEventAccess() else { return }
    let waitingFor = ProcessInfo.processInfo.environment["TYPEFACEOFF_FUZZ_PERMISSION_STAGE"]
    if waitingFor != "event-posting" {
      _ = CGRequestPostEventAccess()
      guard !CGPreflightPostEventAccess() else { return }
      announce(
        "Waiting for event-posting permission for UIFuzzDriver in System Settings > Privacy & Security > Accessibility."
      )
    }
    restartAfterPermissionDelay(stage: "event-posting")
  }

  private static func announce(_ message: String) {
    try? FileHandle.standardOutput.write(contentsOf: Data("\(message)\n".utf8))
  }

  private static func permissionTarget() -> String {
    let bundle = Bundle.main.bundleURL
    if bundle.pathExtension == "app" { return bundle.path }
    return URL(
      fileURLWithPath: CommandLine.arguments[0],
      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ).standardizedFileURL.path
  }

  private static func restartAfterPermissionDelay(stage: String) -> Never {
    setenv("TYPEFACEOFF_FUZZ_PERMISSION_STAGE", stage, 1)
    Thread.sleep(forTimeInterval: 1)
    var arguments = CommandLine.arguments.map { strdup($0) }
    arguments.append(nil)
    _ = arguments.withUnsafeMutableBufferPointer { buffer in
      execv(buffer[0], buffer.baseAddress)
    }
    let message = String(cString: strerror(errno))
    for argument in arguments.compactMap({ $0 }) { free(argument) }
    fatalError("Could not restart ui-fuzz while waiting for permission: \(message)")
  }

  func perform(_ action: FuzzAction) throws {
    try DesktopSession.current().requireAvailable()
    switch action.kind {
    case .press:
      let element = try require(action)
      try perform(kAXPressAction as String, on: element)
    case .setValue:
      let element = try require(action)
      try focus(element)
      let result = AXUIElementSetAttributeValue(
        element, kAXValueAttribute as CFString, (action.value ?? "") as CFTypeRef)
      guard result == .success else { throw DriverError.actionFailed("set value", result) }
      if action.commitValue != false { try postKey(code: 36, modifiers: 0) }
    case .increment:
      try perform(kAXIncrementAction as String, on: require(action))
    case .decrement:
      try perform(kAXDecrementAction as String, on: require(action))
    case .showMenu:
      try perform(kAXShowMenuAction as String, on: require(action))
    case .shortcut, .key:
      try postKey(code: action.keyCode ?? 0, modifiers: action.modifiers ?? 0)
    case .scroll:
      let target = try require(action)
      let point = try center(of: target).unwrap(
        DriverError.actionFailed("locate scroll target", .noValue))
      guard
        let event = CGEvent(
          scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
          wheel1: Int32(action.deltaY ?? 0), wheel2: Int32(action.deltaX ?? 0), wheel3: 0)
      else { throw DriverError.actionFailed("create scroll", .failure) }
      event.location = point
      event.postToPid(processIdentifier)
    case .pause:
      break
    case .selectFont:
      let familyButton = try require(action)
      let search = try revealFontSearch(byPressing: familyButton)
      try focus(search)
      let result = AXUIElementSetAttributeValue(
        search, kAXValueAttribute as CFString, (action.value ?? "") as CFTypeRef)
      guard result == .success else { throw DriverError.actionFailed("set font search", result) }
      Thread.sleep(forTimeInterval: 0.05)
      try postKey(code: 36, modifiers: 0)
    case .click:
      let point = try center(of: require(action)).unwrap(
        DriverError.actionFailed("locate click target", .noValue))
      try postMouse(.leftMouseDown, at: point)
      try postMouse(.leftMouseUp, at: point)
    case .drag:
      let start = try center(of: require(action)).unwrap(
        DriverError.actionFailed("locate drag target", .noValue))
      let end = CGPoint(x: start.x + (action.deltaX ?? 0), y: start.y + (action.deltaY ?? 0))
      try postMouse(.leftMouseDown, at: start)
      for step in 1...5 {
        let fraction = Double(step) / 5
        try postMouse(
          .leftMouseDragged,
          at: CGPoint(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction))
      }
      try postMouse(.leftMouseUp, at: end)
    }
  }

  func snapshot() -> [String] {
    descendants(of: application).compactMap { element in
      let role = stringAttribute(kAXRoleAttribute, of: element) ?? "?"
      let name = names(of: element).sorted().first ?? ""
      return name.isEmpty ? nil : "\(role):\(name)"
    }.sorted()
  }

  private func require(_ target: String?, waiting timeout: TimeInterval = 2) throws -> AXUIElement {
    guard let target else { throw DriverError.controlMissing("<missing target>") }
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    repeat {
      if let result = firstDescendant(of: application, matching: { names(of: $0).contains(target) })
      {
        return result
      }
      if ProcessInfo.processInfo.systemUptime < deadline {
        Thread.sleep(forTimeInterval: 0.05)
      }
    } while ProcessInfo.processInfo.systemUptime < deadline
    throw DriverError.controlMissing(target)
  }

  private func require(_ action: FuzzAction) throws -> AXUIElement {
    guard let path = action.targetPath else { return try require(action.target) }
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    repeat {
      if let element = element(at: path),
        action.targetRole == stringAttribute(kAXRoleAttribute, of: element),
        action.target.map({ names(of: element).contains($0) }) ?? true
      {
        return element
      }
      // SwiftUI can insert siblings during layout. A unique label and role still
      // identify the same control; duplicate or unnamed controls must match the path.
      if let target = action.target {
        let matches = descendants(of: application).filter {
          stringAttribute(kAXRoleAttribute, of: $0) == action.targetRole
            && names(of: $0).contains(target)
        }
        if matches.count == 1 { return matches[0] }
      }
      Thread.sleep(forTimeInterval: 0.05)
    } while ProcessInfo.processInfo.systemUptime < deadline
    throw DriverError.controlMissing(action.target ?? "\(path)")
  }

  private func element(at path: [Int]) -> AXUIElement? {
    var element = application
    for index in path {
      let elements = children(of: element)
      guard elements.indices.contains(index) else { return nil }
      element = elements[index]
    }
    return element
  }

  private func perform(_ action: String, on element: AXUIElement) throws {
    let result = AXUIElementPerformAction(element, action as CFString)
    guard result == .success else { throw DriverError.actionFailed(action, result) }
  }

  private func revealFontSearch(byPressing familyButton: AXUIElement) throws -> AXUIElement {
    for _ in 0..<3 {
      try perform(kAXPressAction as String, on: familyButton)
      if let search = try? require("Search installed fonts", waiting: 1) { return search }
    }
    throw DriverError.controlMissing("Search installed fonts")
  }

  private func focus(_ element: AXUIElement) throws {
    let result = AXUIElementSetAttributeValue(
      element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    guard result == .success else { throw DriverError.actionFailed("focus", result) }
  }

  private func postKey(code: UInt16, modifiers: UInt64) throws {
    // Setting AXFrontmost can time out while AppKit is tracking a menu. Avoid
    // that synchronous accessibility write when delivering keys into menus or sheets.
    if attribute(kAXFrontmostAttribute, of: application) as? Bool != true {
      guard NSRunningApplication(processIdentifier: processIdentifier)?.activate() == true else {
        try DesktopSession.current().requireAvailable()
        throw AvailabilityError(
          signature: "activation",
          detail: "The diagnostic app could not activate in the current desktop session.")
      }
    }
    let source = CGEventSource(stateID: .combinedSessionState)
    guard
      let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    else { throw DriverError.actionFailed("create key event", .failure) }
    let flags = CGEventFlags(rawValue: modifiers)
    down.flags = flags
    up.flags = flags
    down.postToPid(processIdentifier)
    Thread.sleep(forTimeInterval: 0.02)
    up.postToPid(processIdentifier)
  }

  private func postMouse(_ type: CGEventType, at point: CGPoint) throws {
    guard
      let event = CGEvent(
        mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    else { throw DriverError.actionFailed("create mouse event", .failure) }
    event.postToPid(processIdentifier)
  }

  private func descendants(of root: AXUIElement) -> [AXUIElement] {
    var pending = [root]
    var result: [AXUIElement] = []
    var visited = Set<CFHashCode>()
    while let element = pending.popLast(), result.count < 10_000 {
      let identity = CFHash(element)
      guard visited.insert(identity).inserted else { continue }
      result.append(element)
      pending.append(contentsOf: children(of: element).reversed())
    }
    return result
  }

  /// Stop as soon as a control is found; enumerating every system menu can itself stall AppKit.
  private func firstDescendant(
    of root: AXUIElement, matching predicate: (AXUIElement) -> Bool
  ) -> AXUIElement? {
    var pending = [root]
    var visited = Set<CFHashCode>()
    while let element = pending.popLast(), visited.count < 10_000 {
      guard visited.insert(CFHash(element)).inserted else { continue }
      if predicate(element) { return element }
      // Window controls precede the menu bar in the application's accessibility children.
      pending.append(contentsOf: children(of: element).reversed())
    }
    return nil
  }

  private func names(of element: AXUIElement) -> Set<String> {
    Set(
      [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
        .compactMap { stringAttribute($0, of: element) }.filter { !$0.isEmpty })
  }

  private func center(of element: AXUIElement) -> CGPoint? {
    guard let positionValue = attribute(kAXPositionAttribute, of: element),
      let sizeValue = attribute(kAXSizeAttribute, of: element),
      CFGetTypeID(positionValue) == AXValueGetTypeID(),
      CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { return nil }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else { return nil }
    return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
  }

  private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
    attribute(name, of: element) as? String
  }
}

extension Optional {
  fileprivate func unwrap(_ error: @autoclosure () -> Error) throws -> Wrapped {
    guard let self else { throw error() }
    return self
  }
}

func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
    return nil
  }
  return value
}

func children(of element: AXUIElement) -> [AXUIElement] {
  attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
}
