import AppKit
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct FontFamilyPickerTests {
  @Test func theResultListSupportsArrowKeysAndReturn() async throws {
    var chosen: [String?] = []
    let host = WorkbenchTestHost(
      FontFamilyPicker(
        families: ["Alpha", "Beta", "Gamma"], currentFamily: "Alpha", allowsNone: false,
        choose: { chosen.append($0) }), width: 300, height: 400)
    defer { host.window.close() }
    try await host.settle()
    let table = try #require(host.subviews.compactMap { $0 as? NSTableView }.first)
    host.window.makeFirstResponder(table)
    try sendKey(125, characters: "\u{F701}", to: host.window)
    try await host.settle()
    #expect(chosen.isEmpty)
    try sendKey(36, characters: "\r", to: host.window)
    try await host.settle()
    #expect(chosen == ["Beta"])
    try sendKey(126, characters: "\u{F700}", to: host.window)
    try await host.settle()
    try sendKey(36, characters: "\r", to: host.window)
    #expect(chosen == ["Beta", "Alpha"])
    let search = try #require(fontSearch(host))
    for (command, expected) in [
      (#selector(NSResponder.moveDown(_:)), "Alpha"),
      (#selector(NSResponder.moveUp(_:)), "Gamma"),
    ] {
      table.deselectAll(nil)
      try await host.settle()
      host.window.makeFirstResponder(search)
      search.currentEditor()?.doCommand(by: command)
      try await host.settle()
      search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      #expect(chosen.last == expected)
    }
  }

  @Test func searchArrowsAndReturnChooseOnlyTheHighlightedResult() async throws {
    var chosen: [String?] = []
    let host = WorkbenchTestHost(
      FontFamilyPicker(
        families: ["Alpha", "Beta", "Gamma"], currentFamily: "Alpha", allowsNone: true,
        choose: { chosen.append($0) }), width: 300, height: 400)
    defer { host.window.close() }
    try await host.settle()
    let search = try #require(fontSearch(host))
    #expect(search.currentEditor() != nil)
    host.enter("a", in: search)
    try await host.settle()
    search.currentEditor()?.doCommand(by: #selector(NSResponder.moveDown(_:)))
    try await host.settle()
    #expect(chosen.isEmpty)
    let editor = try #require(search.currentEditor() as? NSTextView)
    editor.selectedRange = NSRange(location: 1, length: 0)
    editor.doCommand(by: #selector(NSResponder.moveLeft(_:)))
    #expect(editor.selectedRange.location == 0)
    editor.setMarkedText(
      "a", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: 0, length: 1))
    let delegate = try #require(search.delegate as? PickerSearchField.Coordinator)
    #expect(
      !delegate.control(
        search, textView: editor,
        doCommandBy: #selector(NSResponder.insertNewline(_:))))
    #expect(chosen.isEmpty)
    editor.unmarkText()
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen == ["Beta"])
    search.currentEditor()?.doCommand(by: #selector(NSResponder.moveUp(_:)))
    try await host.settle()
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen == ["Beta", "Alpha"])
    host.enter("GAM", in: search)
    try await host.settle()
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen.last == "Gamma")
    host.enter("No such family", in: search)
    try await host.settle()
    search.currentEditor()?.doCommand(by: #selector(NSResponder.moveDown(_:)))
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen.count == 3)
    host.enter("None", in: search)
    try await host.settle()
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen.count == 4)
    #expect(chosen[3] == nil)
  }

  @Test func cancellingTheFontPopoverPreservesTheComparison() async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 246)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Font A family")
    try await host.settle()
    let search = try #require(fontSearch(host))
    #expect(search.currentEditor() != nil)
    host.enter("Skia", in: search)
    try await host.settle()
    search.currentEditor()?.doCommand(by: #selector(NSResponder.moveDown(_:)))
    #expect(model.comparison == initial)
    search.currentEditor()?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    try await host.settle { fontSearch(host) == nil }
    #expect(model.comparison == initial)
    try await host.press("Font A family")
    try await host.settle()
    let reopened = try #require(fontSearch(host))
    #expect(reopened.currentEditor() != nil)
    #expect(reopened.stringValue.isEmpty)
    host.enter("Skia", in: reopened)
    try await host.settle()
    reopened.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    try await host.settle()
    #expect(model.comparison.a.face.family == "Skia")
    try await host.press("Font A family")
    try await host.settle()
    let table = try #require(host.subviews.compactMap { $0 as? NSTableView }.first)
    let popover = try #require(table.window)
    popover.makeFirstResponder(table)
    try sendKey(53, characters: "\u{1b}", to: popover)
    try await host.settle { fontSearch(host) == nil }
    #expect(model.comparison.a.face.family == "Skia")
  }

  @Test func typingHidesTheSearchPlaceholder() async throws {
    let host = WorkbenchTestHost(FontInspector(model: WorkbenchModel(), side: .a), width: 246)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Font A family")
    try await host.settle { fontSearch(host)?.currentEditor() != nil }
    let search = try #require(fontSearch(host))
    try sendKey(1, characters: "S", to: try #require(search.window))
    try await host.settle()
    #expect(search.stringValue == "S")
    let text = try #require(search.cell as? NSSearchFieldCell).searchTextRect(
      forBounds: search.bounds)
    let band = NSRect(x: text.midX, y: text.midY - 3, width: text.width / 2, height: 6)
    let bitmap = try #require(search.bitmapImageRepForCachingDisplay(in: band))
    search.cacheDisplay(in: band, to: bitmap)
    let brightness = try (0..<bitmap.pixelsHigh).flatMap { y in
      try (0..<bitmap.pixelsWide).map { x in
        try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).brightnessComponent
      }
    }
    let range = try #require(brightness.max()) - #require(brightness.min())
    #expect(range < 0.1)
  }

  private func fontSearch<Content>(_ host: WorkbenchTestHost<Content>) -> NSSearchField? {
    host.subviews.compactMap { $0 as? NSSearchField }.first {
      $0.placeholderString == "Search installed fonts"
    }
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
