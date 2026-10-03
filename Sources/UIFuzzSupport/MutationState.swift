import Foundation

/// The few facts about the workbench that decide whether a control named by label exists.
/// A nil field is unknown, and unknown never satisfies a requirement.
struct WorkbenchState: Equatable, Sendable {
  enum Mode: Sendable { case text, glyph }
  enum Sheet: Sendable { case closed, editor, match }
  enum Popover: Sendable { case closed, fonts, characters }
  enum Inspector: String, Sendable {
    case a = "Font A"
    case b = "Font B"
  }

  enum Requirement: Equatable, Sendable {
    case mode(Mode)
    case sheet(Sheet?)
    case popover(Popover)
    case inspector(Inspector)
    case configuredInspector(Inspector)
  }

  var mode: Mode? = .text
  var sheet: Sheet? = .closed
  var popover: Popover? = .closed
  var appearanceLocked: Bool? = true
  var inspectorAVisible: Bool? = true
  var inspectorBVisible: Bool? = true
  var fontBPresent: Bool? = true
  var fontPickerSide: Inspector?

  static let launch = WorkbenchState()
  static let unknown = WorkbenchState(
    mode: nil, sheet: nil, popover: nil, appearanceLocked: nil,
    inspectorAVisible: nil, inspectorBVisible: nil, fontBPresent: nil)

  private static let command = UInt64(1 << 20)
  private static let shift = UInt64(1 << 17)
  private static let option = UInt64(1 << 19)
  private static let escape = FuzzAction(kind: .key, keyCode: 53, delayMilliseconds: 400)

  static func requirement(of action: FuzzAction) -> Requirement? {
    if action.kind == .showInspector { return nil }
    if let sheet = action.sheet {
      switch sheet {
      case .match: return .sheet(.match)
      case .editor: return .sheet(.editor)
      }
    }
    guard let target = action.target else { return nil }
    switch target {
    case "Glyph canvas", "Character", "Previous character", "Next character",
      "Search characters", "Zoom in", "Zoom out", "Reset glyph zoom", "Glyph zoom":
      return .mode(.glyph)
    case "Font A specimen", "Font B specimen": return .mode(.text)
    case "Custom specimen text": return .sheet(.editor)
    case "Tracking", "Weight", "Size", "Typography", "Refine", "Stop", "Cancel matching",
      "xmark.circle.fill", "Reference A specimen scroll area", "Proposed B specimen scroll area",
      "Match options scroll area", "Match status scroll area", "Optimize", "equal.square":
      return .sheet(.match)
    case let name where name.hasPrefix("Font B Optimize ") || name.hasPrefix("Optimize "):
      return .sheet(.match)
    case "Apply", "Cancel": return .sheet(nil)
    case "Search installed fonts": return .popover(.fonts)
    case "Search Unicode characters": return .popover(.characters)
    case "Font A inspector", "Font B inspector": return nil
    case "Font A family": return .inspector(.a)
    case "Font B family": return .inspector(.b)
    default:
      for side in [Inspector.a, .b] where target.hasPrefix("\(side.rawValue) ") {
        if target.hasPrefix("\(side.rawValue) specimen") { return .mode(.text) }
        return .configuredInspector(side)
      }
      return nil
    }
  }

  func satisfies(_ requirement: Requirement) -> Bool {
    switch requirement {
    case .mode(let mode): self.mode == mode
    case .sheet(let sheet?): self.sheet == sheet && (sheet != .match || fontBPresent == true)
    case .sheet(nil): sheet == .editor || sheet == .match
    case .popover(let popover): self.popover == popover
    case .inspector(.a): inspectorAVisible == true && sheet == .closed
    case .inspector(.b): inspectorBVisible == true && sheet == .closed
    case .configuredInspector(let side):
      satisfies(.inspector(side)) && popover == .closed && (side != .b || fontBPresent == true)
    }
  }

  /// The lock button's label names the action it performs, so it flips with the state.
  func matchingAppearanceLabel(_ action: FuzzAction) -> FuzzAction {
    guard let locked = appearanceLocked,
      action.target == "Lock appearance" || action.target == "Unlock appearance"
    else { return action }
    let label = locked ? "Unlock appearance" : "Lock appearance"
    guard action.target != label else { return action }
    var result = action
    result.target = label
    result.targetPath = nil
    result.targetRole = nil
    return result
  }

  /// Menu shortcuts are disabled while a sheet is up, so overlays are dismissed first and every
  /// enabler starts from a known state. Every enabler sets its state rather than toggling it.
  mutating func enable(_ requirement: Requirement) -> [FuzzAction] {
    var actions: [FuzzAction] = []
    func run(_ action: FuzzAction) {
      actions.append(action)
      apply(action)
    }
    func prepareFontB() {
      if inspectorBVisible != true {
        run(FuzzAction(kind: .showInspector, target: "Font B family", delayMilliseconds: 400))
      }
      run(
        FuzzAction(
          kind: .selectFont, target: "Font B family", value: "Arial", delayMilliseconds: 400))
    }
    while popover != .closed || sheet != .closed { run(Self.escape) }
    switch requirement {
    case .mode(let mode):
      run(
        FuzzAction(
          kind: .shortcut, keyCode: mode == .glyph ? 19 : 18, modifiers: Self.command,
          delayMilliseconds: 50))
    case .sheet(let wanted):
      if wanted == .match && fontBPresent != true { prepareFontB() }
      run(
        FuzzAction(
          kind: .shortcut, keyCode: wanted == .match ? 46 : 14,
          modifiers: Self.command | Self.shift, delayMilliseconds: 400))
    case .popover(let wanted):
      if wanted == .fonts && inspectorAVisible != true {
        run(FuzzAction(kind: .showInspector, target: "Font A family", delayMilliseconds: 400))
      }
      run(
        wanted == .fonts
          ? FuzzAction(kind: .press, target: "Font A family", delayMilliseconds: 400)
          : FuzzAction(
            kind: .shortcut, keyCode: 3, modifiers: Self.command, delayMilliseconds: 400))
    case .inspector(let side):
      run(
        FuzzAction(kind: .showInspector, target: "\(side.rawValue) family", delayMilliseconds: 400))
    case .configuredInspector(let side):
      if !satisfies(.inspector(side)) {
        run(
          FuzzAction(
            kind: .showInspector, target: "\(side.rawValue) family", delayMilliseconds: 400))
      }
      if side == .b && fontBPresent != true { prepareFontB() }
    }
    precondition(satisfies(requirement))
    return actions
  }

  mutating func apply(_ action: FuzzAction) {
    switch action.kind {
    case .shortcut: applyShortcut(action.keyCode, modifiers: action.modifiers)
    case .key: applyKey(action.keyCode)
    case .press, .click, .drag: applyControl(action)
    case .setValue:
      // Committing a search picks a result, which closes its popover.
      if action.target?.hasPrefix("Search ") == true && action.commitValue != false {
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
      sheet = .closed
      popover = .closed
    case .showInspector:
      if action.target == "Font A family" { inspectorAVisible = true }
      if action.target == "Font B family" { inspectorBVisible = true }
      sheet = .closed
      popover = .closed
    case .increment, .decrement:
      if action.target == "Toggle font A inspector" { inspectorAVisible = nil }
      if action.target == "Toggle font B inspector" { inspectorBVisible = nil }
    case .scroll, .pause, .showMenu: break
    }
    // The character search popover closes when the view leaves glyph mode.
    if popover == .characters && mode != .glyph { popover = mode == nil ? nil : .closed }
  }

  private mutating func applyShortcut(_ keyCode: UInt16?, modifiers: UInt64?) {
    let command = Self.command
    let shift = Self.shift
    if keyCode == 6 && (modifiers == command || modifiers == command | shift) {
      appearanceLocked = nil
      fontBPresent = nil
    }
    // A window has its own state.
    if keyCode == 45 && modifiers == command { self = .unknown }
    guard let sheet else {
      mode = nil
      return
    }
    guard sheet == .closed else { return }
    switch (keyCode, modifiers) {
    case (18, command): mode = .text
    case (19, command): mode = .glyph
    case (3, command):
      mode = .glyph
      popover = .characters
    case (14, command | shift): self.sheet = .editor
    case (46, command | shift):
      if fontBPresent == true { self.sheet = .match }
      if fontBPresent == nil { self.sheet = nil }
    case (18, command | Self.option): inspectorAVisible = inspectorAVisible.map { !$0 }
    case (19, command | Self.option): inspectorBVisible = inspectorBVisible.map { !$0 }
    default: break
    }
  }

  private mutating func applyKey(_ keyCode: UInt16?) {
    switch keyCode {
    case 53:
      switch popover {
      case .closed: sheet = .closed
      case nil:
        // Escape closes an open popover before it closes a sheet, and the popover may be closed.
        popover = .closed
        if sheet != .closed { sheet = nil }
      default: popover = .closed
      }
    case 36:
      if popover == .fonts && fontPickerSide == .b { fontBPresent = nil }
      // Return presses the Match sheet's default button, Apply, which is disabled until a fit
      // improves, so whether that sheet closes is unknown and the next requirement dismisses it
      // first. The editor sheet counts as closed.
      if popover != .closed {
        popover = nil
      } else if sheet == .match {
        sheet = nil
      } else if sheet == .editor {
        sheet = .closed
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
    case "Edit text", "Edit sample text…": if sheet == .closed { sheet = .editor }
    case "Match…", "Match fonts…":
      if sheet == .closed && fontBPresent == true { sheet = .match }
      if sheet == .closed && fontBPresent == nil { sheet = nil }
    case "Apply", "Cancel", "Cancel matching", "xmark.circle.fill": sheet = .closed
    case "Search characters":
      mode = .glyph
      popover = .characters
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
    case "Unlock appearance": appearanceLocked = false
    case "Lock appearance": appearanceLocked = true
    case "Undo", "arrow.uturn.backward":
      appearanceLocked = nil
      fontBPresent = nil
    case "Toggle font A inspector", "Font A inspector":
      inspectorAVisible = inspectorAVisible.map { !$0 }
    case "Toggle font B inspector", "Font B inspector":
      inspectorBVisible = inspectorBVisible.map { !$0 }
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
      let action = state.matchingAppearanceLabel(original)
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
