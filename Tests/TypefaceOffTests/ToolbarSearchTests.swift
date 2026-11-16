import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct ToolbarSearchTests {
  @Test func openingResultsKeepsAnActiveSearch() async throws {
    let calls = AsyncStream.makeStream(of: String.self)
    let session = ToolbarSearchSession { query, fonts in
      calls.continuation.yield(query)
      return try await CharacterSearchPickerTests.canned(query, fonts)
    }
    session.search("arrow")
    session.resume()
    try await waitUntil { session.answer?.request.query == "arrow" }
    calls.continuation.finish()
    var queries: [String] = []
    for await query in calls.stream { queries.append(query) }
    #expect(queries == ["arrow"])
  }

  @Test func searchingSelectsOnlyTheCurrentConfirmedResult() async throws {
    let session = ToolbarSearchSession(load: CharacterSearchPickerTests.canned)
    var chosen: [String] = []
    session.choose = { chosen.append($0) }
    session.move(1)
    session.configure(Comparison(b: nil))
    session.search("b")
    session.confirm()
    try await waitUntil { chosen == ["b"] }
    #expect(session.answer?.request.fonts.count == 1)
    session.search("arrow")
    try await waitUntil { session.answer?.request.query == "arrow" }
    session.move(-1)
    #expect(session.selection == Array("←".unicodeScalars))
    session.move(1)
    session.confirm()
    #expect(chosen == ["b", "→"])
    session.selection = nil
    session.move(-1)
    #expect(session.selection == Array("↑".unicodeScalars))
    session.move(1)
    #expect(session.selection == Array("↑".unicodeScalars))
    session.selection = nil
    session.move(1)
    #expect(session.selection == Array("←".unicodeScalars))
    session.configure(Comparison())
    try await waitUntil { session.answer?.request.fonts.count == 2 }
    session.configure(Comparison())
    session.search("no results")
    session.confirm()
    try await waitUntil { session.answer?.request.query == "no results" }
    session.move(1)
    session.confirm()
    #expect(chosen == ["b", "→"])
    session.search("b")
    session.cancel()
    await Task.yield()
    #expect(chosen == ["b", "→"])
    session.resume()
    session.confirm()
    try await waitUntil { chosen == ["b", "→", "b"] }
    session.resume()
    session.search("arrow")
    try await waitUntil { session.answer?.request.query == "arrow" }
  }

  @Test func anchoredResultsShowHintsEmptyStatesAndKeyboardSelection() async throws {
    let model = WorkbenchModel()
    var chosen: [String] = []
    let host = WorkbenchTestHost(
      ToolbarSearch(
        comparison: model.comparison, languages: model.languages, focus: .constant(false),
        choose: { chosen.append($0) }, load: CharacterSearchPickerTests.canned
      ).frame(width: 200), width: 440, height: 100)
    defer { host.window.close() }
    try await host.settle()
    let field = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
    let coordinator = try #require(field.delegate as? ToolbarSearch.Coordinator)
    coordinator.controlTextDidBeginEditing(
      Notification(name: NSControl.textDidBeginEditingNotification))
    try await host.settle()
    #expect(coordinator.popover.isShown)
    host.enter("arrow", in: field)
    try await host.settle { coordinator.session.answer?.request.query == "arrow" }
    let editor = try #require(field.currentEditor())
    editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
    try await host.settle()
    #expect(coordinator.session.selection == Array("→".unicodeScalars))
    let selected = CharacterSearchResult(glyph: "→", supported: [true, true])
    let label = CharacterSearchRow.label(
      selected, names: CharacterSearchRow.names(of: coordinator.session.request.fonts))
    try await host.press(label)
    #expect(chosen == ["→"])
    #expect(!coordinator.popover.isShown)
    host.enter("no results", in: field)
    try await host.settle { coordinator.session.answer?.request.query == "no results" }
    #expect(coordinator.popover.isShown)
    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    #expect(!coordinator.popover.isShown)
    var spacing = model.comparison
    spacing.shape = false
    spacing.spacing = true
    host.setContent(
      ToolbarSearch(
        comparison: spacing, languages: model.languages, focus: .constant(false),
        choose: { chosen.append($0) }, load: CharacterSearchPickerTests.canned
      ).frame(width: 200))
    try await host.settle()
    host.enter("b", in: field)
    try await host.settle { coordinator.session.answer?.request.query == "b" }
    try await host.submit("b", to: field)
    try await host.settle { chosen == ["→", "b"] }
  }

  @Test func literalSearchIdentityPreservesUnicodeScalars() {
    let angstrom = CharacterSearchModel.Request(query: "\u{212b}", fonts: [])
    let ring = CharacterSearchModel.Request(query: "\u{00c5}", fonts: [])
    #expect(angstrom.query == ring.query)
    #expect(angstrom != ring)
    #expect(angstrom == CharacterSearchModel.Request(query: "\u{212b}", fonts: []))
  }

  @Test func searchDelegateRespectsCompositionAndClosesWithEscape() async throws {
    let model = WorkbenchModel()
    let search = ToolbarSearch(
      comparison: model.comparison, languages: model.languages, focus: .constant(false),
      choose: { _ in })
    let coordinator = search.makeCoordinator()
    let field = NSSearchField()
    coordinator.field = field
    let editor = NSTextView()
    editor.setMarkedText(
      "e", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(
      !coordinator.control(
        field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
    editor.unmarkText()
    #expect(
      !coordinator.control(
        field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    for selector in [
      #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)),
      #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)),
    ] {
      #expect(coordinator.control(field, textView: editor, doCommandBy: selector))
    }
    var languages = model.comparison
    languages.mode = .languages
    coordinator.parent = ToolbarSearch(
      comparison: languages, languages: model.languages, focus: .constant(false), choose: { _ in })
    #expect(
      !coordinator.control(
        field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    coordinator.field = nil
    coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    ToolbarSearch.dismantleNSView(field, coordinator: coordinator)
  }
}
