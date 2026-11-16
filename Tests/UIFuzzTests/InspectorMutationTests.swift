import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct InspectorMutationTests {
  private let reveal = FuzzAction(
    kind: .showInspector, target: "Comparison inspector scroll area", delayMilliseconds: 400)

  @Test(arguments: ["A", "B"])
  func inspectorControlsRevealTheSingleInspector(side: String) {
    let drag = FuzzAction(kind: .drag, target: "Font \(side) Tracking", deltaX: 30, deltaY: 0)
    let toggle = FuzzAction(kind: .press, target: "Show Inspector")
    #expect(TraceMutator().repaired([drag]) == [reveal, drag])
    #expect(TraceMutator().repaired([toggle, drag]) == [toggle, drag])
    let repaired = TraceMutator().repaired([toggle, toggle, drag])
    #expect(repaired == [toggle, toggle, reveal, drag])
    #expect(TraceMutator().repaired(repaired) == repaired)
  }

  @Test(arguments: ["A", "B"])
  func headerControlsNeverNeedTheInspector(side: String) {
    let toggle = FuzzAction(kind: .press, target: "Show Inspector")
    for name in [
      "family", "style", "Size field", "Tracking field stepper", "typography", "other axes",
    ] {
      let action = FuzzAction(kind: .press, target: "Font \(side) \(name)")
      #expect(TraceMutator().repaired([action]) == [action])
      #expect(TraceMutator().repaired([toggle, toggle, action]) == [toggle, toggle, action])
    }
  }

  @Test func inspectorShortcutsAndUnknownWindowsNeedAReveal() {
    let toggle = FuzzAction(kind: .shortcut, keyCode: 34, modifiers: UInt64((1 << 20) | (1 << 18)))
    let field = FuzzAction(kind: .setValue, target: "Font B Inspector Size field", value: "44")
    let newWindow = FuzzAction(kind: .shortcut, keyCode: 45, modifiers: UInt64(1 << 20))
    #expect(TraceMutator().repaired([toggle, field]) == [toggle, field])
    for prefix in [[toggle, toggle], [newWindow]] {
      let repaired = TraceMutator().repaired(prefix + [field])
      #expect(repaired.dropLast().contains(reveal))
      #expect(repaired.last == field)
      #expect(TraceMutator().repaired(repaired) == repaired)
    }
  }

  @Test(arguments: ["Typography", "Open typography inspector"])
  func compactTypographyRevealsTheInspectorWithoutReopeningIt(target: String) {
    let typography = FuzzAction(kind: .press, target: target)
    let field = FuzzAction(kind: .setValue, target: "Font A Inspector Size field", value: "24")
    #expect(TraceMutator().repaired([typography, field]) == [typography, field])
    let editor = FuzzAction(
      kind: .shortcut, keyCode: 14, modifiers: UInt64((1 << 20) | (1 << 17)))
    let repaired = TraceMutator().repaired([editor, typography, field])
    #expect(repaired.map(\.kind) == [.shortcut, .key, .press, .setValue])
    #expect(repaired[1].keyCode == 53)
  }

  @Test func fontSearchDismissesTheEditorWithoutOpeningTheInspector() {
    let edit = FuzzAction(kind: .shortcut, keyCode: 14, modifiers: UInt64((1 << 20) | (1 << 17)))
    let search = FuzzAction(kind: .setValue, target: "Search installed fonts", value: "Skia")
    let repaired = TraceMutator().repaired([edit, search])
    #expect(repaired.map(\.kind) == [.shortcut, .key, .press, .setValue])
    #expect(repaired[1].keyCode == 53)
    #expect(repaired[2].target == "Font A family")
  }

  @Test func uncertainButtonActionsDoNotClaimTheInspectorIsVisible() {
    var state = WorkbenchState.launch
    for kind in [FuzzAction.Kind.increment, .decrement] {
      state.apply(FuzzAction(kind: kind, target: "Show Inspector"))
      #expect(state.inspectorVisible == nil)
      #expect(state.enable(.inspector) == [reveal])
      #expect(state.satisfies(.inspector))
    }
  }

  @Test func theActionBudgetIncludesRevealingTheInspector() {
    let drag = FuzzAction(kind: .drag, target: "Font A Tracking", deltaX: 30, deltaY: 0)
    #expect(TraceMutator(maximumActions: 2).repaired([drag]) == [reveal, drag])
    #expect(TraceMutator(maximumActions: 1).repaired([drag]).first?.kind == .pause)
  }

  @Test func revealsRoundTripWithoutNeedingAnAccessibilityTarget() throws {
    #expect(try JSONDecoder().decode(FuzzAction.self, from: JSONEncoder().encode(reveal)) == reveal)
    #expect(!reveal.kind.needsTarget)
    var state = WorkbenchState.unknown
    state.apply(reveal)
    #expect(state.inspectorVisible == true)
    #expect(state.sheet == .closed && state.popover == .closed)
  }

  @Test(arguments: [false, true])
  func numericControlsAndMatchingRestoreARemovedFontB(showInspector: Bool) {
    let none = FuzzAction(kind: .selectFont, target: "Font B family", value: "None")
    let prefix = [none] + (showInspector ? [reveal] : [])
    for control in [
      FuzzAction(kind: .increment, target: "Font B Tracking"),
      FuzzAction(kind: .setValue, target: "Font B Size field", value: "22"),
      FuzzAction(kind: .press, target: "Font B Optimize tracking"),
    ] {
      let repaired = TraceMutator().repaired(prefix + [control])
      #expect(repaired.contains { $0.kind == .selectFont && $0.value == "Arial" })
      #expect(repaired.last == control)
      #expect(TraceMutator().repaired(repaired) == repaired)
    }
  }

  @Test func selectingNoneFromThePickerDoesNotPretendMatchingOpens() {
    var state = WorkbenchState.launch
    state.apply(FuzzAction(kind: .press, target: "Font B family"))
    state.apply(FuzzAction(kind: .press, target: "None"))
    state.apply(FuzzAction(kind: .shortcut, keyCode: 46, modifiers: UInt64((1 << 20) | (1 << 17))))
    #expect(state.fontBPresent == false)
    #expect(state.sheet == .closed)
    _ = state.enable(.sheet(.match))
    #expect(state.fontBPresent == true)
    #expect(state.satisfies(.sheet(.match)))
  }

  @Test func matchingAfterUndoDoesNotClaimAnUnknownFontBIsPresent() {
    for match in [
      FuzzAction(kind: .press, target: "Match…"),
      FuzzAction(kind: .shortcut, keyCode: 46, modifiers: UInt64((1 << 20) | (1 << 17))),
    ] {
      var state = WorkbenchState.launch
      state.apply(FuzzAction(kind: .press, target: "Undo"))
      state.apply(match)
      #expect(state.sheet == nil)
      _ = state.enable(.sheet(.match))
      #expect(state.fontBPresent == true)
      #expect(state.satisfies(.sheet(.match)))
    }
  }

  @Test func inspectorEditsDismissOverlaysAndFamilyButtonsDismissSheets() {
    let editor = FuzzAction(kind: .shortcut, keyCode: 14, modifiers: UInt64((1 << 20) | (1 << 17)))
    let family = FuzzAction(kind: .press, target: "Font A family")
    let tracking = FuzzAction(kind: .increment, target: "Font A Tracking")
    let repaired = TraceMutator().repaired([editor, family, tracking])
    #expect(repaired.map(\.kind) == [.shortcut, .key, .press, .key, .showInspector, .increment])
    #expect(TraceMutator().repaired(repaired) == repaired)
  }

  @Test func pickerConfirmationAndUndoMakeFontBPresenceUnknown() {
    let family = FuzzAction(kind: .press, target: "Font B family")
    let search = FuzzAction(kind: .setValue, target: "Search installed fonts", value: "None")
    let undo = FuzzAction(kind: .shortcut, keyCode: 6, modifiers: UInt64(1 << 20))
    for actions in [
      [family, search], [family, FuzzAction(kind: .key, keyCode: 36)], [undo],
      [FuzzAction(kind: .press, target: "Undo")],
    ] {
      var state = WorkbenchState.launch
      for action in actions { state.apply(action) }
      #expect(state.fontBPresent == nil)
      let control = FuzzAction(kind: .increment, target: "Font B Tracking")
      let repaired = TraceMutator().repaired(actions + [control])
      #expect(repaired.contains { $0.kind == .selectFont && $0.value == "Arial" })
      #expect(repaired.last == control)
      #expect(TraceMutator().repaired(repaired) == repaired)
    }
    var state = WorkbenchState.launch
    state.apply(family)
    var draft = search
    draft.commitValue = false
    state.apply(draft)
    #expect(state.fontBPresent == true)
  }

  @Test func toolbarSearchKeepsTheCurrentModeUntilACharacterIsChosen() {
    for mode in [WorkbenchState.Mode.text, .glyph, .languages] {
      var state = WorkbenchState(mode: mode)
      state.apply(FuzzAction(kind: .shortcut, keyCode: 3, modifiers: UInt64(1 << 20)))
      #expect(state.mode == mode)
      #expect(state.popover == (mode == .languages ? .closed : .characters))
      state.apply(FuzzAction(kind: .setValue, target: "Search Languages", value: "English"))
      #expect(state.mode == mode)
    }
    var state = WorkbenchState.launch
    state.apply(
      FuzzAction(kind: .setValue, target: "Find Character", value: "arrow", commitValue: false))
    #expect(state.mode == .text && state.popover == .characters)
    state.apply(FuzzAction(kind: .setValue, target: "Find Character", value: "U+0041"))
    #expect(state.mode == nil && state.popover == nil)
    for initial in [WorkbenchState.launch, .unknown, WorkbenchState(mode: .languages)] {
      var state = initial
      _ = state.enable(.characterSearch)
      #expect(state.satisfies(.characterSearch))
      _ = state.enable(.popover(.characters))
      #expect(state.satisfies(.popover(.characters)))
    }
    state.apply(
      FuzzAction(kind: .setValue, target: "Find Character", value: "arrow", commitValue: false))
    state.apply(FuzzAction(kind: .shortcut, keyCode: 20, modifiers: UInt64(1 << 20)))
    #expect(state.popover == .closed)
    for mode in [WorkbenchState.Mode?.none, .text, .glyph, .languages] {
      var state = WorkbenchState(mode: mode)
      state.apply(FuzzAction(kind: .press, target: "Find Character"))
      #expect(state.mode == mode)
      #expect(state.popover == (mode == .languages ? .closed : mode == nil ? nil : .characters))
    }
  }

  @Test(arguments: [
    "Comparison inspector scroll area", "Inspector appearance link", "Reset appearance section",
    "Reset typography section", "Reset paired leading", "Reset feature ot.kern",
    "Select typography ot.kern",
  ])
  func sharedInspectorControlsRequireThePanel(target: String) {
    #expect(WorkbenchState.requirement(of: .init(kind: .press, target: target)) == .inspector)
    var state = WorkbenchState.unknown
    _ = state.enable(.inspector)
    #expect(state.satisfies(.inspector))
  }
}
