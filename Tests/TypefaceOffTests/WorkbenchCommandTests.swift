import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct WorkbenchCommandTests {
  @Test func menuActionsUseTheirDocumentAndPreserveUndo() async throws {
    let first = CommandFixture()
    let initial = first.document.comparison
    let second = CommandFixture(comparison: Comparison(b: nil))
    let host = WorkbenchTestHost(CommandTestView(fixture: first, document: first.document))
    defer { host.window.close() }
    try await host.settle()
    first.undo.beginUndoGrouping()
    try host.press("Swap fonts")
    first.undo.endUndoGrouping()
    try await host.settle()
    #expect(first.document.comparison.a == initial.b)
    #expect(first.document.comparison.b == initial.a)
    #expect(second.document.comparison.b == nil)
    first.undo.undo()
    #expect(first.document.comparison.a == initial.a)
    #expect(first.document.comparison.b == initial.b)
    try host.press("Glyph view")
    try await host.settle()
    #expect(first.document.comparison.mode == .glyph)
    try host.press("Glyph view")
    #expect(first.document.comparison.mode == .glyph)
    try host.press("Text view")
    try await host.settle()
    #expect(first.document.comparison.mode == .text)
    #expect(first.undo.canRedo)
    try host.press("Highlight shape differences")
    try host.press("Highlight spacing differences")
    #expect(first.document.comparison.shape != initial.shape)
    #expect(first.document.comparison.spacing != initial.spacing)
    try host.press("Font A inspector")
    try host.press("Font B inspector")
    #expect(!first.showA && !first.showB)
    try host.press("Edit sample text…")
    try host.press("Match fonts…")
    #expect(first.editRequested && first.matchRequested)
    host.view.rootView = AnyView(
      CommandTestView(fixture: second, document: second.document)
        .environment(\.accessibilityEnabled, true))
    try await host.settle()
    #expect(try host.element("Swap fonts").isAccessibilityEnabled?() == false)
    #expect(try host.element("Match fonts…").isAccessibilityEnabled?() == false)
    try host.press("Glyph view")
    #expect(second.document.comparison.mode == .glyph)
    #expect(first.document.comparison.mode == .text)
    second.document.comparison = Comparison(a: .init("Missing-Font"))
    try await host.settle()
    #expect(try host.element("Match fonts…").isAccessibilityEnabled?() == false)
    #expect(try host.element("Swap fonts").isAccessibilityEnabled?() == true)
  }

  @Test func commandsAreDisabledWithoutAnAvailableWorkbench() async throws {
    let host = WorkbenchTestHost(
      VStack {
        WorkbenchMenuItems(section: .inspectors, actions: nil)
        WorkbenchMenuItems(section: .view, actions: nil)
        WorkbenchMenuItems(section: .comparison, actions: nil)
      })
    defer { host.window.close() }
    try await host.settle()
    for title in [
      "Font A inspector", "Font B inspector", "Text view", "Glyph view",
      "Highlight shape differences", "Highlight spacing differences", "Match fonts…",
      "Swap fonts", "Edit sample text…",
    ] {
      #expect(try host.element(title).isAccessibilityEnabled?() == false)
    }
  }
}

private struct CommandTestView: View {
  @ObservedObject var fixture: CommandFixture
  @ObservedObject var document: WorkbenchDocument

  var body: some View {
    let actions = fixture.actions
    VStack {
      WorkbenchMenuItems(section: .inspectors, actions: actions)
      WorkbenchMenuItems(section: .view, actions: actions)
      WorkbenchMenuItems(section: .comparison, actions: actions)
    }
  }
}

@MainActor private final class CommandFixture: ObservableObject {
  let document: WorkbenchDocument
  let undo = UndoManager()
  @Published var showA = true
  @Published var showB = true
  var matchRequested = false
  var editRequested = false

  init(comparison: Comparison = Comparison()) {
    document = WorkbenchDocument(comparison: comparison)
    undo.groupsByEvent = false
  }

  var actions: WorkbenchActions {
    WorkbenchActions(
      document: document, undoManager: undo,
      showA: Binding(get: { self.showA }, set: { self.showA = $0 }),
      showB: Binding(get: { self.showB }, set: { self.showB = $0 }),
      mode: presentation(\.mode), shape: presentation(\.shape), spacing: presentation(\.spacing),
      match: { self.matchRequested = true }, editText: { self.editRequested = true })
  }

  private func presentation<Value>(_ key: WritableKeyPath<Comparison, Value>) -> Binding<Value> {
    Binding(
      get: { self.document.comparison[keyPath: key] },
      set: { value in self.document.updatePresentation { $0[keyPath: key] = value } })
  }
}
