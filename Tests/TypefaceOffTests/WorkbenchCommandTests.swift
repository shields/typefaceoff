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
    try await host.press("Swap fonts")
    first.undo.endUndoGrouping()
    try await host.settle()
    #expect(first.model.comparison.a == initial.b)
    #expect(first.model.comparison.b == initial.a)
    #expect(second.model.comparison.b == nil)
    first.undo.undo()
    #expect(first.model.comparison.a == initial.a)
    #expect(first.model.comparison.b == initial.b)
    try await host.press("Glyph view")
    try await host.settle()
    #expect(first.model.comparison.mode == .glyph)
    try await host.press("Glyph view")
    #expect(first.model.comparison.mode == .glyph)
    try await host.press("Text view")
    try await host.settle()
    #expect(first.model.comparison.mode == .text)
    #expect(first.undo.canRedo)
    try await host.press("Highlight shape differences")
    try await host.press("Highlight spacing differences")
    try await host.press("Weight by character frequency")
    #expect(first.model.comparison.shape != initial.shape)
    #expect(first.model.comparison.spacing != initial.spacing)
    #expect(first.model.comparison.frequency != initial.frequency)
    try await host.press("Font A inspector")
    try await host.press("Font B inspector")
    #expect(!first.showA && !first.showB)
    try await host.press("Edit sample text…")
    try await host.press("Match fonts…")
    #expect(first.editRequested && first.matchRequested)
    try await host.press("Find character…")
    #expect(first.searching)
    host.setContent(CommandTestView(fixture: second, model: second.model))
    try await host.settle()
    #expect(try await host.element("Swap fonts").isAccessibilityEnabled?() == false)
    #expect(try await host.element("Match fonts…").isAccessibilityEnabled?() == false)
    try await host.press("Glyph view")
    #expect(second.model.comparison.mode == .glyph)
    #expect(first.model.comparison.mode == .text)
    second.model.comparison = Comparison(a: .init("Missing-Font"))
    try await host.settle()
    #expect(try await host.element("Match fonts…").isAccessibilityEnabled?() == false)
    #expect(try await host.element("Swap fonts").isAccessibilityEnabled?() == true)
  }

  @Test func findCharacterIsTheOnlyCommandF() throws {
    func items(_ menu: NSMenu) -> [NSMenuItem] {
      menu.items + menu.items.compactMap(\.submenu).flatMap(items)
    }
    let commandF = items(try #require(NSApp.mainMenu)).filter {
      $0.keyEquivalent == "f" && $0.keyEquivalentModifierMask == .command
    }
    #expect(commandF.map(\.title) == ["Find character…"])
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
      "Find character…", "Font A inspector", "Font B inspector", "Text view", "Glyph view",
      "Highlight shape differences", "Highlight spacing differences",
      "Weight by character frequency", "Match fonts…", "Swap fonts", "Edit sample text…",
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
  @Published var showA = true
  @Published var showB = true
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
      showA: Binding(get: { self.showA }, set: { self.showA = $0 }),
      showB: Binding(get: { self.showB }, set: { self.showB = $0 }),
      mode: presentation(\.mode), shape: presentation(\.shape), spacing: presentation(\.spacing),
      frequency: presentation(\.frequency),
      characterSearch: Binding(get: { self.searching }, set: { self.searching = $0 }),
      match: { self.matchRequested = true },
      editText: { self.editRequested = true })
  }

  private func presentation<Value>(_ key: WritableKeyPath<Comparison, Value>) -> Binding<Value> {
    Binding(
      get: { self.model.comparison[keyPath: key] },
      set: { value in self.model.updatePresentation { $0[keyPath: key] = value } })
  }
}
