import Foundation

/// The few facts about the workbench that decide whether a control named by label exists.
/// A nil field is unknown, and unknown never satisfies a requirement.
struct WorkbenchState: Equatable, Sendable {
  enum Mode: Sendable { case text, glyph, languages }
  enum Operation: Sendable { case closed, editor, match }
  enum Popover: Sendable {
    case closed, fonts, characters, glyphCharacters, matchAxes, matchTypography
  }
  enum Inspector: String, Sendable {
    case a = "Font A"
    case b = "Font B"
  }

  enum Requirement: Equatable, Sendable {
    case mode(Mode)
    case editable
    case operation(Operation?)
    case popover(Popover)
    case family(Inspector)
    case header(Inspector)
    case inspector
    case characterSearch
    case configuredInspector(Inspector)
  }

  var mode: Mode? = .text
  var operation: Operation? = .closed
  var popover: Popover? = .closed
  var inspectorVisible: Bool? = false
  var fontBPresent: Bool? = true
  var fontPickerSide: Inspector?

  static let launch = WorkbenchState()
  static let unknown = WorkbenchState(
    mode: nil, operation: nil, popover: nil, inspectorVisible: nil, fontBPresent: nil)

  private static let command = UInt64(1 << 20)
  private static let shift = UInt64(1 << 17)
  private static let control = UInt64(1 << 18)
  private static let escape = FuzzAction(kind: .key, keyCode: 53, delayMilliseconds: 400)

  static func requirement(of action: FuzzAction) -> Requirement? {
    if action.kind == .showInspector || action.kind == .setSpecimen { return .editable }
    if action.targetRole == "AXMenuItem", let target = action.target {
      if target.hasPrefix("Font B Optimize axis ") { return .popover(.matchAxes) }
      if target.hasPrefix("Font B Optimize feature ") { return .popover(.matchTypography) }
    }
    if let operation = action.context {
      switch operation {
      case .match: return .operation(.match)
      case .editor: return .operation(.editor)
      }
    }
    guard let target = action.target else { return nil }
    switch target {
    case "Glyph canvas", "Character", "Previous character", "Next character",
      "Search characters", "Zoom in", "Zoom out", "Reset glyph zoom", "Glyph zoom":
      return .mode(.glyph)
    case "Font A specimen", "Font B specimen": return .mode(.text)
    case let name where name.hasPrefix("Language ") || name.hasPrefix("Inspect language "):
      return .mode(.languages)
    case "Search Languages", "Search languages", "Minimum speaker count",
      "Minimum language speakers",
      "Show historical", "Use as specimen",
      "Clear filters":
      return .mode(.languages)
    case "Custom specimen text": return .operation(.editor)
    case "Stop", "Cancel matching": return .operation(.match)
    case let name where name.hasPrefix("Font B Optimize "):
      return .operation(.match)
    case "Apply", "Cancel": return .operation(nil)
    case "Search installed fonts": return .popover(.fonts)
    case "Search Unicode characters": return .popover(.glyphCharacters)
    case "Find Character": return .characterSearch
    case "Show Inspector", "Toggle comparison inspector", "Sample selector", "Swap fonts",
      "Swap Fonts", "arrow.up.arrow.down", "Header appearance link",
      "Link A and B", "Link Appearance", "Make Sizes Equal", "Reset Appearance", "Reset Typography":
      return .editable
    case "Typography", "Open typography inspector": return .header(.a)
    case let name
    where name.hasPrefix("Reset paired ") || name.hasPrefix("Reset feature ")
      || name.hasPrefix("Select typography "):
      return .inspector
    case "Font A family": return .family(.a)
    case "Font B family": return .family(.b)
    case "Comparison inspector scroll area", "Inspector appearance link",
      "Reset appearance section",
      "Reset typography section":
      return .inspector
    default:
      for side in [Inspector.a, .b] where target.hasPrefix("\(side.rawValue) ") {
        if target.hasPrefix("\(side.rawValue) specimen") { return .mode(.text) }
        let label = String(target.dropFirst(side.rawValue.count + 1))
        if ["style", "typography", "other axes"].contains(label)
          || ["Size", "Weight", "Leading", "Tracking"].contains(where: {
            label == "\($0) field" || label == "\($0) field stepper"
          })
        {
          return .header(side)
        }
        return .configuredInspector(side)
      }
      return nil
    }
  }

  func satisfies(_ requirement: Requirement) -> Bool {
    switch requirement {
    case .mode(let mode):
      self.mode == mode && (operation == .closed || (operation == .match && mode != .languages))
    case .editable: operation == .closed && popover == .closed
    case .operation(let operation?):
      self.operation == operation && (operation != .match || fontBPresent == true)
    case .operation(nil): operation == .editor || operation == .match
    case .popover(.matchAxes):
      popover == .matchAxes && operation == .match && fontBPresent == true
    case .popover(.matchTypography):
      popover == .matchTypography && operation == .match && fontBPresent == true
    case .popover(let popover):
      self.popover == popover
        && (operation == .closed || (operation == .match && popover != .fonts))
    case .family: operation == .closed
    case .header(let side):
      operation == .closed && popover == .closed && (side != .b || fontBPresent == true)
    case .inspector: inspectorVisible == true && operation == .closed && popover == .closed
    case .configuredInspector(let side): satisfies(.inspector) && satisfies(.header(side))
    case .characterSearch:
      (operation == .closed || operation == .match) && (mode == .text || mode == .glyph)
    }
  }

  mutating func enable(_ requirement: Requirement) -> [FuzzAction] {
    var actions: [FuzzAction] = []
    func run(_ action: FuzzAction) {
      actions.append(action)
      apply(action)
    }
    func prepareFontB() {
      run(
        FuzzAction(
          kind: .selectFont, target: "Font B family", value: "Arial", delayMilliseconds: 400))
    }
    let permitsMatch: Bool
    switch requirement {
    case .mode(let mode): permitsMatch = mode != .languages
    case .popover(.matchAxes), .popover(.matchTypography): permitsMatch = fontBPresent == true
    case .popover(let popover): permitsMatch = popover != .fonts
    case .characterSearch: permitsMatch = true
    default: permitsMatch = false
    }
    while popover != .closed || (operation != .closed && !(permitsMatch && operation == .match)) {
      run(Self.escape)
    }
    switch requirement {
    case .mode(let mode):
      run(
        FuzzAction(
          kind: .shortcut, keyCode: mode == .glyph ? 19 : mode == .languages ? 20 : 18,
          modifiers: Self.command,
          delayMilliseconds: 50))
    case .operation(let wanted):
      if wanted == .match && fontBPresent != true { prepareFontB() }
      run(
        FuzzAction(
          kind: .shortcut, keyCode: wanted == .match ? 46 : 14,
          modifiers: Self.command | Self.shift, delayMilliseconds: 400))
    case .popover(let wanted):
      if wanted == .matchAxes || wanted == .matchTypography {
        if !satisfies(.operation(.match)) {
          if fontBPresent != true { prepareFontB() }
          run(
            FuzzAction(
              kind: .shortcut, keyCode: 46, modifiers: Self.command | Self.shift,
              delayMilliseconds: 400))
        }
        run(
          FuzzAction(
            kind: .press,
            target: wanted == .matchAxes ? "Font B Optimize axes" : "Font B Optimize typography",
            delayMilliseconds: 400))
        break
      }
      if wanted == .characters && mode != .text && mode != .glyph {
        run(
          FuzzAction(kind: .shortcut, keyCode: 18, modifiers: Self.command, delayMilliseconds: 50))
      }
      if wanted == .glyphCharacters && mode != .glyph {
        run(
          FuzzAction(kind: .shortcut, keyCode: 19, modifiers: Self.command, delayMilliseconds: 50))
      }
      run(
        wanted == .fonts
          ? FuzzAction(kind: .press, target: "Font A family", delayMilliseconds: 400)
          : wanted == .glyphCharacters
            ? FuzzAction(kind: .press, target: "Search characters", delayMilliseconds: 400)
            : FuzzAction(
              kind: .shortcut, keyCode: 3, modifiers: Self.command, delayMilliseconds: 400))
    case .family, .editable: break
    case .header(let side):
      if side == .b && fontBPresent != true { prepareFontB() }
    case .inspector, .configuredInspector:
      if !satisfies(.inspector) {
        run(
          FuzzAction(
            kind: .showInspector, target: "Comparison inspector scroll area", delayMilliseconds: 400
          ))
      }
      if case .configuredInspector(.b) = requirement, fontBPresent != true { prepareFontB() }
    case .characterSearch:
      if mode != .text && mode != .glyph {
        run(
          FuzzAction(kind: .shortcut, keyCode: 18, modifiers: Self.command, delayMilliseconds: 50))
      }
    }
    precondition(satisfies(requirement))
    return actions
  }

  mutating func apply(_ action: FuzzAction) {
    switch action.kind {
    case .shortcut: applyShortcut(action.keyCode, modifiers: action.modifiers)
    case .key: applyKey(action.keyCode)
    case .press, .click, .drag, .showMenu: applyControl(action)
    case .setValue:
      // Committing a search picks a result, which closes its popover.
      if action.target == "Find Character" {
        if action.commitValue != false { mode = nil }
        popover = action.commitValue == false ? .characters : nil
      } else if ["Search installed fonts", "Search Unicode characters"].contains(action.target)
        && action.commitValue != false
      {
        if action.target == "Search installed fonts" && fontPickerSide == .b {
          fontBPresent = nil
        }
        popover = nil
      }
    case .selectFont:
      if action.target == "Font B family" {
        fontBPresent = action.value.map { !$0.isEmpty && $0 != "None" }
      }
      popover = .closed
      fontPickerSide = nil
    case .setSpecimen:
      operation = .closed
      popover = .closed
    case .showInspector:
      inspectorVisible = true
      operation = .closed
      popover = .closed
    case .increment, .decrement:
      if ["Show Inspector", "Toggle comparison inspector"].contains(action.target) {
        inspectorVisible = nil
      }
    case .scroll, .pause: break
    }
    if popover == .characters && mode == .languages { popover = .closed }
    if popover == .glyphCharacters && mode != .glyph { popover = mode == nil ? nil : .closed }
  }

  private mutating func applyShortcut(_ keyCode: UInt16?, modifiers: UInt64?) {
    let command = Self.command
    let shift = Self.shift
    if keyCode == 6 && (modifiers == command || modifiers == command | shift) {
      fontBPresent = nil
    }
    // A window has its own state.
    if keyCode == 45 && modifiers == command { self = .unknown }
    guard let operation else {
      mode = nil
      return
    }
    guard operation != .editor else { return }
    switch (keyCode, modifiers) {
    case (18, command): mode = .text
    case (19, command): mode = .glyph
    case (20, command): if operation == .closed { mode = .languages }
    case (3, command):
      popover = mode == .languages ? .closed : mode == nil ? nil : .characters
    case (14, command | shift): if operation == .closed { self.operation = .editor }
    case (46, command | shift): openMatch()
    case (34, command | Self.control):
      if operation == .closed { inspectorVisible = inspectorVisible.map { !$0 } }
    default: break
    }
  }

  private mutating func openMatch() {
    guard operation == .closed else { return }
    if fontBPresent == true {
      operation = .match
      if mode == .languages { mode = .text }
    }
    if fontBPresent == nil { operation = nil }
  }

  private mutating func applyKey(_ keyCode: UInt16?) {
    switch keyCode {
    case 53:
      switch popover {
      case .closed: operation = .closed
      case nil:
        // An unknown popover can consume Escape before it reaches the active operation.
        popover = .closed
        if operation != .closed { operation = nil }
      default: popover = .closed
      }
    case 36:
      if popover == .fonts && fontPickerSide == .b { fontBPresent = nil }
      if popover != .closed {
        popover = nil
      } else if operation == .match {
        operation = nil
      } else if operation == .editor {
        operation = .closed
      }
    default: break
    }
  }

  private mutating func applyControl(_ action: FuzzAction) {
    guard let target = action.target else { return }
    switch target {
    case "Glyph canvas":
      // Pressing the canvas returns to text; a mouse click does too unless the glyph is zoomed.
      mode = action.kind == .press ? .text : nil
    case "Glyph": mode = .glyph
    case "Text": mode = .text
    case "Languages", "Languages view": if operation == .closed { mode = .languages }
    case "Language use specimen button", "Use as specimen": mode = .text
    case let name where name.hasPrefix("Language missing ") && !name.hasSuffix(" disclosure"):
      mode = .glyph
    case "Edit Text…", "Edit Sample Text…": if operation == .closed { operation = .editor }
    case "Match…", "Match fonts…": openMatch()
    case "Font B Optimize axes": popover = .matchAxes
    case "Font B Optimize typography": popover = .matchTypography
    case let target
    where target.hasPrefix("Font B Optimize axis ") || target.hasPrefix("Font B Optimize feature "):
      if action.targetRole == "AXMenuItem" { popover = .closed }
    case "Apply", "Cancel", "Cancel matching": operation = .closed
    case "Search characters":
      mode = .glyph
      popover = .glyphCharacters
    case "Font A specimen", "Font B specimen":
      // A mouse click that lands on a character enters glyph mode; an AXPress does not.
      if action.kind != .press { mode = nil }
    case "Font A family", "Font B family":
      fontPickerSide = target == "Font A family" ? .a : .b
      // An AXPress runs the button's action, which opens the popover and never dismisses one.
      switch (popover, action.kind) {
      case (.closed, _), (.fonts, .press): popover = .fonts
      default: popover = nil
      }
    case "None":
      if popover == .fonts && fontPickerSide == .b {
        fontBPresent = false
        popover = .closed
        fontPickerSide = nil
      }
    case "Undo", "arrow.uturn.backward":
      fontBPresent = nil
    case "Show Inspector", "Toggle comparison inspector":
      inspectorVisible = inspectorVisible.map { !$0 }
    case "Font A typography", "Font B typography", "Font A other axes", "Font B other axes",
      "Typography", "Open typography inspector":
      inspectorVisible = true
    case "Find Character", "Search Languages":
      popover = mode == .languages ? .closed : mode == nil ? nil : .characters
    default:
      if target.hasPrefix("Inspect ") { mode = .glyph }
    }
  }
}

extension TraceMutator {
  /// A step that cannot fit its enablers becomes a pause, so the plan keeps its length.
  func repaired(_ actions: [FuzzAction]) -> [FuzzAction] {
    var state = WorkbenchState.launch
    var result: [FuzzAction] = []
    for (index, original) in actions.enumerated() {
      // Discovery no longer offers such an item, but a recorded trace still names it.
      if original.targetRole == "AXMenuItem",
        let target = original.target,
        SystemMenuItems.opensSystemUI(identifier: target, title: target)
      {
        result.append(FuzzAction(kind: .pause, delayMilliseconds: 1))
        continue
      }
      var next = state
      let action = original
      var enablers: [FuzzAction] = []
      if let requirement = WorkbenchState.requirement(of: action), !next.satisfies(requirement) {
        enablers = next.enable(requirement)
      }
      let remaining = actions.count - index - 1
      guard result.count + enablers.count + 1 + remaining <= maximumActions else {
        result.append(FuzzAction(kind: .pause, delayMilliseconds: 1))
        continue
      }
      next.apply(action)
      state = next
      result += enablers + [action]
    }
    return result
  }
}
