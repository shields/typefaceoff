import AppKit
import SwiftUI
import Synchronization
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct CharacterSearchPickerTests {
  nonisolated static func canned(_ query: String, _ fonts: [FontConfiguration]) async throws
    -> [CharacterSearchResult]
  {
    let glyphs =
      switch query {
      case "arrow": ["←", "→", "↑"]
      case "b": ["b"]
      default: [String]()
      }
    return glyphs.map { CharacterSearchResult(glyph: $0, supported: fonts.map { _ in true }) }
  }

  func searchField<Content>(_ host: WorkbenchTestHost<Content>) -> NSSearchField? {
    host.subviews.compactMap { $0 as? NSSearchField }.first {
      $0.placeholderString == "Search Unicode characters"
    }
  }

  func table<Content>(_ host: WorkbenchTestHost<Content>) -> NSTableView? {
    host.subviews.compactMap { $0 as? NSTableView }.first
  }

  @Test func searchKeysChooseOnlyTheHighlightedCharacter() async throws {
    var chosen: [String] = []
    let host = WorkbenchTestHost(
      CharacterSearchPicker(comparison: Comparison(), load: Self.canned) { chosen.append($0) },
      width: 440, height: 460)
    defer { host.window.close() }
    try await host.settle()
    let search = try #require(searchField(host))
    #expect(search.currentEditor() != nil)
    _ = try await host.element("Character search hint")
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    host.enter("arrow", in: search)
    try await host.settle { table(host) != nil }
    search.currentEditor()?.doCommand(by: #selector(NSResponder.moveDown(_:)))
    try await host.settle()
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen == ["→"])
    search.currentEditor()?.doCommand(by: #selector(NSResponder.moveUp(_:)))
    try await host.settle()
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen == ["→", "←"])
    let list = try #require(table(host))
    for (command, expected) in [
      (#selector(NSResponder.moveDown(_:)), "←"), (#selector(NSResponder.moveUp(_:)), "↑"),
    ] {
      list.deselectAll(nil)
      try await host.settle()
      host.window.makeFirstResponder(search)
      search.currentEditor()?.doCommand(by: command)
      try await host.settle()
      search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      #expect(chosen.last == expected)
    }
    host.window.makeFirstResponder(list)
    try sendKey(126, characters: "\u{F700}", to: host.window)
    try await host.settle()
    try sendKey(36, characters: "\r", to: host.window)
    #expect(chosen.last == "→")
    try await host.press(unicodeDescription("←"))
    #expect(chosen.last == "←")
    try sendKey(53, characters: "\u{1b}", to: host.window)
    host.window.makeFirstResponder(search)
    host.enter("zzzz", in: search)
    try await host.settle { table(host) == nil }
    _ = try await host.element("No matching characters")
    let count = chosen.count
    search.currentEditor()?.doCommand(by: #selector(NSResponder.moveDown(_:)))
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    search.currentEditor()?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    try await host.settle()
    #expect(chosen.count == count)
  }

  @Test func returnWaitsForTheCurrentQuerysResults() async throws {
    let (requests, started) = AsyncStream<String>.makeStream()
    let loader = SuspendedCharacterSearch(started: started)
    var chosen: [String] = []
    let host = WorkbenchTestHost(
      CharacterSearchPicker(
        comparison: Comparison(), load: { query, _ in await loader.load(query) }
      ) {
        chosen.append($0)
      }, width: 440, height: 460)
    defer { host.window.close() }
    var iterator = requests.makeAsyncIterator()
    try await host.settle()
    let search = try #require(searchField(host))
    host.enter("x", in: search)
    #expect(await iterator.next() == "x")
    try await host.settle { host.subviews.contains { $0 is NSProgressIndicator } }
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen.isEmpty)
    await loader.finish("x", with: ["x"])
    try await host.settle { chosen == ["x"] }
    host.enter("zz", in: search)
    #expect(await iterator.next() == "zz")
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    await loader.finish("zz", with: [])
    try await host.settle { table(host) == nil }
    _ = try await host.element("No matching characters")
    host.enter("y", in: search)
    #expect(await iterator.next() == "y")
    await loader.finish("y", with: ["y"])
    try await host.settle { table(host) != nil }
    #expect(chosen == ["x"])
  }

  @Test(arguments: [false, true])
  func obsoleteSearchesCannotReplaceCurrentResults(cancel: Bool) async {
    let (requests, started) = AsyncStream<String>.makeStream()
    let loader = SuspendedCharacterSearch(started: started)
    let model = CharacterSearchModel { query, _ in await loader.load(query) }
    var iterator = requests.makeAsyncIterator()
    let old = CharacterSearchModel.Request(query: "a", fonts: [])
    let current = CharacterSearchModel.Request(query: "b", fonts: [])
    let oldTask = Task { await model.update(old) }
    #expect(await iterator.next() == "a")
    if cancel { oldTask.cancel() }
    let currentTask = Task { await model.update(current) }
    #expect(await iterator.next() == "b")
    await loader.finish("b", with: ["b"])
    await currentTask.value
    #expect(model.answer?.request == current)
    await loader.finish("a", with: ["a"])
    await oldTask.value
    #expect(model.answer?.request == current)
    #expect(model.answer?.results.map(\.glyph) == ["b"])
  }

  @Test func changingFontsSearchesAgain() async throws {
    let requests = Mutex<[[FontConfiguration]]>([])
    let load: CharacterSearchModel.Load = { query, fonts in
      requests.withLock { $0.append(fonts) }
      return try await Self.canned(query, fonts)
    }
    let host = WorkbenchTestHost(
      CharacterSearchPicker(comparison: Comparison(), load: load) { _ in },
      width: 440, height: 460)
    defer { host.window.close() }
    try await host.settle()
    host.setContent(CharacterSearchPicker(comparison: Comparison(b: nil), load: load) { _ in })
    try await host.settle {
      requests.withLock { $0.last } == [FontConfiguration("HelveticaNeue")]
    }
  }

  @Test func rowsNameAndDrawOnlyTheFontsThatHaveTheCharacter() async throws {
    let helvetica = FontConfiguration("HelveticaNeue")
    let names = CharacterSearchRow.names(of: [helvetica, FontConfiguration("ArialMT")])
    #expect(names == ["Helvetica Neue", "Arial"])
    #expect(
      CharacterSearchRow.names(of: [helvetica, FontConfiguration("HelveticaNeue-Bold")])
        == ["Helvetica Neue Regular", "Helvetica Neue Bold"])
    #expect(
      CharacterSearchRow.names(of: [FontConfiguration("TypefaceOff-Does-Not-Exist")])
        == ["TypefaceOff-Does-Not-Exist"])
    let cases: [([Bool], [String], String?)] = [
      ([true], ["Helvetica Neue"], nil),
      ([false], ["Helvetica Neue"], "Unavailable in Helvetica Neue"),
      ([true, true], names, nil),
      ([false, true], names, "Unavailable in Helvetica Neue"),
      ([true, false], names, "Unavailable in Arial"),
      ([false, false], names, "Unavailable in Helvetica Neue and Arial"),
      ([false, false], ["Arial", "Arial"], "Unavailable in Arial"),
    ]
    for (supported, names, expected) in cases {
      let result = CharacterSearchResult(glyph: "→", supported: supported)
      #expect(CharacterSearchRow.unavailability(result, names: names) == expected)
      #expect(
        CharacterSearchRow.label(result, names: names)
          == "U+2192 RIGHTWARDS ARROW" + (expected.map { ". \($0)" } ?? ""))
    }
    let results = ["a", "b", "c", "d"].enumerated().map { index, glyph in
      CharacterSearchResult(glyph: glyph, supported: [index % 2 == 0, index < 2])
    }
    var spacing = Comparison()
    spacing.spacing = true
    let host = WorkbenchTestHost(
      CharacterSearchPicker(comparison: spacing, load: { _, _ in results }) { _ in },
      width: 440, height: 460)
    defer { host.window.close() }
    try await host.settle()
    host.enter("letter", in: try #require(searchField(host)))
    try await host.settle { table(host) != nil }
    _ = try await host.element(
      "U+0064 LATIN SMALL LETTER D. Unavailable in Helvetica Neue and Arial")
  }

  @Test func workbenchSearchInspectsWithoutUndoAndCloses() async throws {
    var comparison = Comparison()
    comparison.mode = .glyph
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    for (query, glyph) in [
      ("leftwards arrow", "←"), ("U+2192", "→"), ("u+1f984", "🦄"), ("U+E000", "\u{E000}"),
    ] {
      try await host.press("Search characters")
      try await host.settle { searchField(host) != nil }
      let search = try #require(searchField(host))
      host.enter(query, in: search)
      search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      try await host.settle {
        model.comparison.selectedGlyph.unicodeScalars.elementsEqual(glyph.unicodeScalars)
          && searchField(host) == nil
      }
      #expect(host.window.undoManager?.canUndo == false)
      #expect(model.comparison.mode == .glyph)
      #expect(host.window.firstResponder is GlyphDrawingView)
    }
    let inspected = model.comparison
    try await host.press("Search characters")
    try await host.settle { searchField(host) != nil }
    let search = try #require(searchField(host))
    host.enter("arrow", in: search)
    try await host.settle { table(host) != nil }
    search.currentEditor()?.doCommand(by: #selector(NSResponder.moveDown(_:)))
    search.currentEditor()?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    try await host.settle { searchField(host) == nil }
    #expect(model.comparison == inspected)
  }

  @Test func leavingTheGlyphViewClosesTheSearch() async throws {
    var comparison = Comparison()
    comparison.mode = .glyph
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Search characters")
    try await host.settle { searchField(host) != nil }
    model.updatePresentation { $0.mode = .text }
    try await host.settle { searchField(host) == nil }
    model.updatePresentation { $0.mode = .glyph }
    try await host.settle()
    #expect(searchField(host) == nil)
  }

  @Test func findCharacterOpensTheSearchFromTheTextView() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(FindCharacterProbe(model: model))
    defer { host.window.close() }
    try await host.settle { host.isEnabled("Probe find character") }
    try await host.press("Probe find character")
    try await host.settle { searchField(host) != nil }
    let search = try #require(searchField(host))
    #expect(model.comparison.mode == .glyph)
    search.window?.makeFirstResponder(search)
    let editor = try #require(search.currentEditor())
    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    try await host.settle { searchField(host) == nil }
  }

  @Test func aRequestedSearchOpensWithTheGlyphView() async throws {
    let host = WorkbenchTestHost(RequestedSearch())
    defer { host.window.close() }
    try await host.settle { searchField(host) != nil }
    try #require(searchField(host)).currentEditor()?.doCommand(
      by: #selector(NSResponder.cancelOperation(_:)))
    try await host.settle { searchField(host) == nil }
  }

  private func sendKey(_ code: UInt16, characters: String, to window: NSWindow) throws {
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil,
        characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
        keyCode: code))
    window.sendEvent(event)
  }
}

private struct FindCharacterProbe: View {
  let model: WorkbenchModel
  @FocusedValue(\.workbenchActions) private var actions

  var body: some View {
    VStack {
      Button("Probe find character") { actions?.characterSearch.wrappedValue = true }
        .disabled(actions == nil)
      WorkbenchView(model: model)
    }
  }
}

private struct RequestedSearch: View {
  @State private var searching = true

  var body: some View {
    var comparison = Comparison(b: nil)
    comparison.mode = .glyph
    return GlyphComparisonView(
      comparison: comparison, focusRequest: UUID(), searching: $searching, select: { _ in },
      navigate: { _ in }, showText: {}, focusChanged: { _ in })
  }
}

private actor SuspendedCharacterSearch {
  let started: AsyncStream<String>.Continuation
  var pending: [String: CheckedContinuation<[CharacterSearchResult], Never>] = [:]

  init(started: AsyncStream<String>.Continuation) { self.started = started }

  func load(_ query: String) async -> [CharacterSearchResult] {
    guard !query.isEmpty else { return [] }
    return await withCheckedContinuation {
      pending[query] = $0
      started.yield(query)
    }
  }

  func finish(_ query: String, with glyphs: [String]) {
    pending.removeValue(forKey: query)?.resume(
      returning: glyphs.map { CharacterSearchResult(glyph: $0, supported: [true, true]) })
  }
}
