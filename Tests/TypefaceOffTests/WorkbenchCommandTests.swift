import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct WorkbenchCommandTests {
  @Test func menuActionsUseTheirWindowModelAndPreserveUndo() async throws {
    let first = CommandFixture()
    let initial = first.model.comparison
    let second = CommandFixture(comparison: Comparison(b: nil))
    let host = WorkbenchTestHost(CommandTestView(fixture: first, model: first.model))
    defer { host.window.close() }
    try await host.settle()
    first.undo.beginUndoGrouping()
    try await host.press("Swap Fonts")
    first.undo.endUndoGrouping()
    try await host.settle()
    #expect(first.model.comparison.a == initial.b)
    #expect(first.model.comparison.b == initial.a)
    #expect(second.model.comparison.b == nil)
    first.undo.undo()
    #expect(first.model.comparison.a == initial.a)
    #expect(first.model.comparison.b == initial.b)
    try await host.press("Glyph")
    try await host.settle()
    #expect(first.model.comparison.mode == .glyph)
    try await host.press("Glyph")
    #expect(first.model.comparison.mode == .glyph)
    try await host.press("Languages")
    #expect(first.model.comparison.mode == .languages)
    try await host.press("Text")
    try await host.settle()
    #expect(first.model.comparison.mode == .text)
    #expect(first.undo.canRedo)
    try await host.press("Shape")
    try await host.press("Spacing")
    try await host.press("Frequency")
    #expect(first.model.comparison.shape != initial.shape)
    #expect(first.model.comparison.spacing != initial.spacing)
    #expect(first.model.comparison.frequency != initial.frequency)
    try await host.press("Show Inspector")
    #expect(first.inspector)
    try await host.press("Font A")
    #expect(first.focusedFont == .a)
    try await host.press("Font B")
    #expect(first.focusedFont == .b)
    try await host.press("Edit Sample Text…")
    try await host.press("Match…")
    #expect(first.editRequested && first.matchRequested)
    try await host.press("Find Character")
    #expect(first.searching)
    host.setContent(CommandTestView(fixture: second, model: second.model))
    try await host.settle()
    #expect(try await host.element("Swap Fonts").isAccessibilityEnabled?() == false)
    #expect(try await host.element("Match…").isAccessibilityEnabled?() == false)
    try await host.press("Glyph")
    #expect(second.model.comparison.mode == .glyph)
    #expect(first.model.comparison.mode == .text)
    second.model.comparison = Comparison(a: .init("Missing-Font"))
    try await host.settle()
    #expect(try await host.element("Match…").isAccessibilityEnabled?() == false)
    #expect(try await host.element("Swap Fonts").isAccessibilityEnabled?() == true)
  }

  @Test func appearanceCommandsKeepCalibrationAndEachEditCanBeUndone() async throws {
    var comparison = Comparison()
    comparison.a.size = 20
    comparison.b?.size = 24
    comparison.a.tracking = 0.01
    comparison.b?.tracking = 0.04
    comparison.a.features["ot.kern"] = 0
    comparison.calibrate()
    let fixture = CommandFixture(comparison: comparison)
    let host = WorkbenchTestHost(CommandTestView(fixture: fixture, model: fixture.model))
    defer { host.window.close() }
    try await host.settle()
    for title in ["Link Appearance", "Make Sizes Equal", "Reset Appearance", "Reset Typography"] {
      fixture.undo.beginUndoGrouping()
      try await host.press(title)
      fixture.undo.endUndoGrouping()
      let result = fixture.model.comparison
      switch title {
      case "Link Appearance": #expect(!result.appearanceLocked)
      case "Make Sizes Equal":
        #expect(result.a.size == 20 && result.b?.size == 20)
        #expect(result.link?.sizeRatio == 1)
        #expect(result.link?.trackingOffset == comparison.link?.trackingOffset)
      case "Reset Appearance":
        #expect(result.a.size == 22 && result.b?.size == 22)
        #expect(result.a.tracking == 0 && result.b?.tracking == 0)
        #expect(result.a.features == comparison.a.features)
      default:
        #expect(result.a.features.isEmpty)
        #expect(result.a.size == 20 && result.b?.size == 24)
      }
      fixture.undo.undo()
      #expect(fixture.model.comparison == comparison)
      try await host.settle()
    }
    try await host.press("Glyph")
    try await host.press("Zoom In")
    #expect(fixture.zoom == 1.25)
    try await host.press("Zoom Out")
    #expect(fixture.zoom == 1)
    #expect(try await host.element("Zoom Out").isAccessibilityEnabled?() == false)
    fixture.zoom = 8
    try await host.settle()
    #expect(try await host.element("Zoom In").isAccessibilityEnabled?() == false)
    try await host.press("Actual Size")
    #expect(fixture.zoom == 1)
    try await host.press("Previous Character")
    try await host.press("Next Character")
    #expect(fixture.navigation == [-1, 1])
    try await host.press("Languages")
    try await host.press("Search Languages")
    #expect(fixture.searching)
    #expect(try await host.element("Zoom In").isAccessibilityEnabled?() == false)
    #expect(try await host.element("Actual Size").isAccessibilityEnabled?() == false)
  }

  @Test func findCharacterIsTheOnlyCommandF() throws {
    func items(_ menu: NSMenu) -> [NSMenuItem] {
      menu.items + menu.items.compactMap(\.submenu).flatMap(items)
    }
    let commandF = items(try #require(NSApp.mainMenu)).filter {
      $0.keyEquivalent == "f" && $0.keyEquivalentModifierMask == .command
    }
    #expect(commandF.map(\.title) == ["Find Character"])
  }

  @Test func commandsAreDisabledWithoutAnAvailableWorkbench() async throws {
    let host = WorkbenchTestHost(
      VStack {
        WorkbenchMenuItems(section: .find, actions: nil)
        WorkbenchMenuItems(section: .inspectors, actions: nil)
        WorkbenchMenuItems(section: .view, actions: nil)
        WorkbenchMenuItems(section: .comparison, actions: nil)
      })
    defer { host.window.close() }
    try await host.settle()
    for title in [
      "Find Character", "Show Inspector", "Font A", "Font B", "Text", "Glyph",
      "Languages",
      "Shape", "Spacing",
      "Frequency", "Match…", "Swap Fonts", "Edit Sample Text…", "Zoom In", "Zoom Out",
      "Actual Size", "Previous Character", "Next Character", "Link Appearance", "Make Sizes Equal",
      "Reset Appearance", "Reset Typography",
    ] {
      #expect(try await host.element(title).isAccessibilityEnabled?() == false)
    }
  }
}

private struct CommandTestView: View {
  @ObservedObject var fixture: CommandFixture
  @ObservedObject var model: WorkbenchModel

  var body: some View {
    let actions = fixture.actions
    VStack {
      WorkbenchMenuItems(section: .find, actions: actions)
      WorkbenchMenuItems(section: .inspectors, actions: actions)
      WorkbenchMenuItems(section: .view, actions: actions)
      WorkbenchMenuItems(section: .comparison, actions: actions)
    }
  }
}

@MainActor private final class CommandFixture: ObservableObject {
  let model: WorkbenchModel
  let undo = UndoManager()
  @Published var inspector = false
  @Published var zoom = 1.0
  var focusedFont: Side?
  var navigation: [Int] = []
  @Published var searching = false
  var matchRequested = false
  var editRequested = false

  init(comparison: Comparison = Comparison()) {
    model = WorkbenchModel(comparison: comparison)
    undo.groupsByEvent = false
  }

  var actions: WorkbenchActions {
    WorkbenchActions(
      model: model, undoManager: undo,
      inspector: Binding(get: { self.inspector }, set: { self.inspector = $0 }),
      mode: presentation(\.mode), shape: presentation(\.shape), spacing: presentation(\.spacing),
      frequency: presentation(\.frequency),
      zoom: Binding(get: { self.zoom }, set: { self.zoom = $0 }),
      find: { self.searching = true }, focusFont: { self.focusedFont = $0 },
      navigate: { self.navigation.append($0) },
      match: { self.matchRequested = true },
      editText: { self.editRequested = true })
  }

  private func presentation<Value>(_ key: WritableKeyPath<Comparison, Value>) -> Binding<Value> {
    Binding(
      get: { self.model.comparison[keyPath: key] },
      set: { value in self.model.updatePresentation { $0[keyPath: key] = value } })
  }
}
