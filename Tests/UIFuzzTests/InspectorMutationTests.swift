import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct InspectorMutationTests {
  @Test(arguments: ["A", "B"])
  func inspectorControlsAreRevealedAfterAToggle(side: String) {
    let toggle = FuzzAction(kind: .press, target: "Toggle font \(side) inspector")
    let drag = FuzzAction(kind: .drag, target: "Font \(side) Tracking", deltaX: 30, deltaY: 0)
    let repaired = TraceMutator().repaired([toggle, drag])
    #expect(repaired.count == 3)
    #expect(repaired[1].kind == .showInspector)
    #expect(repaired[1].target == "Font \(side) family")
    #expect(!repaired[1].kind.needsTarget)
    #expect(repaired.last == drag)
    #expect(TraceMutator().repaired(repaired) == repaired)
  }

  @Test(arguments: [UInt16(18), 19])
  func inspectorShortcutsAndUnknownWindowsNeedAReveal(code: UInt16) {
    let side = code == 18 ? "A" : "B"
    let toggle = FuzzAction(
      kind: .shortcut, keyCode: code, modifiers: UInt64((1 << 20) | (1 << 19)))
    let field = FuzzAction(kind: .setValue, target: "Font \(side) Size field", value: "44")
    let newWindow = FuzzAction(kind: .shortcut, keyCode: 45, modifiers: UInt64(1 << 20))
    for first in [toggle, newWindow] {
      let repaired = TraceMutator().repaired([first, field])
      #expect(repaired.dropLast().contains { $0.kind == .showInspector })
      #expect(repaired.last == field)
      #expect(TraceMutator().repaired(repaired) == repaired)
    }
  }

  @Test func fontSearchRevealsItsInspectorAndClosesAnEditor() {
    let hide = FuzzAction(kind: .click, target: "Toggle font A inspector")
    let edit = FuzzAction(kind: .shortcut, keyCode: 14, modifiers: UInt64((1 << 20) | (1 << 17)))
    let search = FuzzAction(kind: .setValue, target: "Search installed fonts", value: "Skia")
    let repaired = TraceMutator().repaired([hide, edit, search])
    #expect(repaired.map(\.kind) == [.click, .shortcut, .key, .showInspector, .press, .setValue])
    #expect(repaired[2].keyCode == 53)
    #expect(repaired[3].target == "Font A family")
    #expect(repaired.last == search)
  }

  @Test func uncertainButtonActionsDoNotClaimAnInspectorIsVisible() {
    var state = WorkbenchState.launch
    state.apply(FuzzAction(kind: .increment, target: "Toggle font B inspector"))
    #expect(state.inspectorBVisible == nil)
    let actions = state.enable(.inspector(.b))
    #expect(actions.map(\.kind) == [.showInspector])
    #expect(state.satisfies(.inspector(.b)))
    state.apply(FuzzAction(kind: .decrement, target: "Toggle font A inspector"))
    #expect(state.inspectorAVisible == nil)
  }

  @Test func visibleInspectorsNeedNoRevealAndTheActionBudgetStillApplies() {
    let drag = FuzzAction(kind: .drag, target: "Font A Tracking", deltaX: 30, deltaY: 0)
    #expect(TraceMutator().repaired([drag]) == [drag])
    let toggle = FuzzAction(kind: .press, target: "Toggle font A inspector")
    let repaired = TraceMutator(maximumActions: 2).repaired([toggle, drag])
    #expect(repaired.count == 2)
    #expect(repaired.last?.kind == .pause)
  }

  @Test func revealsRoundTripWithoutNeedingAnAccessibilityTarget() throws {
    let action = FuzzAction(kind: .showInspector, target: "Font B family")
    #expect(try JSONDecoder().decode(FuzzAction.self, from: JSONEncoder().encode(action)) == action)
    var state = WorkbenchState.unknown
    state.apply(action)
    #expect(state.inspectorBVisible == true)
    #expect(state.sheet == .closed && state.popover == .closed)
  }

  @Test(arguments: [false, true])
  func numericControlsAndMatchingRestoreARemovedFontB(hideInspector: Bool) {
    let none = FuzzAction(kind: .selectFont, target: "Font B family", value: "None")
    let prefix =
      [none]
      + (hideInspector ? [FuzzAction(kind: .press, target: "Toggle font B inspector")] : [])
    for control in [
      FuzzAction(kind: .increment, target: "Font B Tracking"),
      FuzzAction(kind: .press, target: "Tracking"),
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
    let editor = FuzzAction(
      kind: .shortcut, keyCode: 14, modifiers: UInt64((1 << 20) | (1 << 17)))
    let family = FuzzAction(kind: .press, target: "Font A family")
    let tracking = FuzzAction(kind: .increment, target: "Font A Tracking")
    let repaired = TraceMutator().repaired([editor, family, tracking])
    #expect(repaired.map(\.kind) == [.shortcut, .key, .showInspector, .press, .key, .increment])
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
}
