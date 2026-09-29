import Foundation

/// The few facts about the workbench that decide whether a control named by label exists.
/// A nil field is unknown, and unknown never satisfies a requirement.
struct WorkbenchState: Equatable, Sendable {
  enum Mode: Sendable { case text, glyph }
  enum Sheet: Sendable { case closed, editor, match }
  enum Popover: Sendable { case closed, fonts, characters }

  enum Requirement: Equatable, Sendable {
    case mode(Mode)
    case sheet(Sheet?)
    case popover(Popover)
  }

  var mode: Mode? = .text
  var sheet: Sheet? = .closed
  var popover: Popover? = .closed
  var appearanceLocked: Bool? = true

  static let launch = WorkbenchState()
  static let unknown = WorkbenchState(
    mode: nil, sheet: nil, popover: nil, appearanceLocked: nil)

  private static let command = UInt64(1 << 20)
  private static let shift = UInt64(1 << 17)
  private static let escape = FuzzAction(kind: .key, keyCode: 53, delayMilliseconds: 400)

  /// A control that exists only while the workbench is in some state, keyed by its label.
  static func requirement(of action: FuzzAction) -> Requirement? {
    guard let target = action.target else { return nil }
    switch target {
    case "Glyph canvas", "Character", "Previous character", "Next character",
      "Search characters", "Zoom in", "Zoom out", "Reset glyph zoom", "Glyph zoom":
      return .mode(.glyph)
    case "Font A specimen", "Font B specimen": return .mode(.text)
    case "Custom specimen text": return .sheet(.editor)
    case "Tracking", "Weight": return .sheet(.match)
    case "Apply", "Cancel": return .sheet(nil)
    case "Search installed fonts": return .popover(.fonts)
    case "Search Unicode characters": return .popover(.characters)
    default: return nil
    }
  }

  func satisfies(_ requirement: Requirement) -> Bool {
    switch requirement {
    case .mode(let mode): self.mode == mode
    case .sheet(let sheet?): self.sheet == sheet
    case .sheet(nil): sheet == .editor || sheet == .match
    case .popover(let popover): self.popover == popover
    }
  }

  /// The lock button's label names the action it performs, so it flips with the state.
  func matchingAppearanceLabel(_ action: FuzzAction) -> FuzzAction {
    guard let locked = appearanceLocked,
      action.target == "Lock appearance" || action.target == "Unlock appearance"
    else { return action }
    var result = action
    result.target = locked ? "Unlock appearance" : "Lock appearance"
    result.targetPath = nil
    result.targetRole = nil
    return result
  }

  /// Actions that establish the requirement from any state, applying them to this state.
  ///
  /// Menu shortcuts are disabled while a sheet is up, and a popover can swallow them, so
  /// overlays are dismissed first. Every enabler sets its state rather than toggling it.
  mutating func enable(_ requirement: Requirement) -> [FuzzAction] {
    var actions: [FuzzAction] = []
    func run(_ action: FuzzAction) {
      actions.append(action)
      apply(action)
    }
    while popover != .closed || sheet != .closed { run(Self.escape) }
    switch requirement {
    case .mode(let mode):
      run(
        FuzzAction(
          kind: .shortcut, keyCode: mode == .glyph ? 19 : 18, modifiers: Self.command,
          delayMilliseconds: 50))
    case .sheet(let wanted):
      run(
        FuzzAction(
          kind: .shortcut, keyCode: wanted == .match ? 46 : 14,
          modifiers: Self.command | Self.shift, delayMilliseconds: 400))
    case .popover(let wanted):
      run(
        wanted == .fonts
          ? FuzzAction(kind: .press, target: "Font A family", delayMilliseconds: 400)
          : FuzzAction(
            kind: .shortcut, keyCode: 3, modifiers: Self.command, delayMilliseconds: 400))
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
        popover = nil
      }
    case .selectFont: popover = .closed
    case .increment, .decrement, .scroll, .pause, .showMenu: break
    }
  }

  private mutating func applyShortcut(_ keyCode: UInt16?, modifiers: UInt64?) {
    let command = Self.command
    let shift = Self.shift
    if keyCode == 6 && (modifiers == command || modifiers == command | shift) {
      appearanceLocked = nil
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
    case (46, command | shift): self.sheet = .match
    default: break
    }
  }

  private mutating func applyKey(_ keyCode: UInt16?) {
    switch keyCode {
    case 53:
      if popover == .closed { sheet = .closed } else { popover = .closed }
    case 36:
      if popover != .closed {
        popover = nil
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
    case "Edit text": if sheet == .closed { sheet = .editor }
    case "Match…": if sheet == .closed { sheet = .match }
    case "Apply", "Cancel": sheet = .closed
    case "Search characters":
      mode = .glyph
      popover = .characters
    case "Font A family", "Font B family":
      // Pressing the button of an open popover dismisses it.
      switch popover {
      case .closed: popover = .fonts
      case .fonts: popover = .closed
      default: popover = nil
      }
    case "Unlock appearance": appearanceLocked = false
    case "Lock appearance": appearanceLocked = true
    case "Undo", "arrow.uturn.backward": appearanceLocked = nil
    default:
      if target.hasPrefix("Inspect ") { mode = .glyph }
    }
  }
}

extension TraceMutator {
  /// Precede each label-addressed control with whatever makes it exist, within `maximumActions`.
  ///
  /// A step that cannot fit its enablers becomes a pause, so the plan keeps its length.
  func repaired(_ actions: [FuzzAction]) -> [FuzzAction] {
    var state = WorkbenchState.launch
    var result: [FuzzAction] = []
    for (index, original) in actions.enumerated() {
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
