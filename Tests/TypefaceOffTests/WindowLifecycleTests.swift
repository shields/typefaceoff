import AppKit
import Testing

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct WindowLifecycleTests {
  @Test func comparisonsAreIndependentUndoableAndDiscardedOnClose() async throws {
    #expect(NSApp.activationPolicy() == .prohibited)
    #expect(!NSApp.isActive)
    #expect(NSApp.windows.contains { $0.isVisible && $0.title == "Helvetica Neue vs. Arial" })
    let fileMenu = try #require(NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu)
    #expect(
      !fileMenu.items.contains { item in
        ["Open", "Save", "Revert", "Duplicate", "Rename", "Move To"].contains {
          item.title.hasPrefix($0)
        }
      })
    #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") == nil)
    #expect(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") == nil)

    let first = try await newWindow(fileMenu)
    defer { first.close() }
    let firstSize = try sizeField(in: first)
    #expect(firstSize.stringValue == "22")
    #expect(!first.isRestorable)
    let undo = try #require(first.undoManager)
    submit("44", to: firstSize)
    try await settle(first) { undo.canUndo }
    first.makeFirstResponder(nil)
    #expect(firstSize.stringValue == "44")
    #expect(undo.canUndo)
    #expect(!first.isDocumentEdited)

    let second = try await newWindow(fileMenu)
    defer { second.close() }
    let secondSize = try sizeField(in: second)
    #expect(secondSize.stringValue == "22")
    #expect(second.undoManager !== undo)
    try editCommand(modifiers: .command, window: first)
    try await settle(first) { firstSize.stringValue == "22" }
    #expect(firstSize.stringValue == "22")
    try editCommand(modifiers: [.command, .shift], window: first)
    try await settle(first) { firstSize.stringValue == "44" }
    #expect(firstSize.stringValue == "44")
    #expect(secondSize.stringValue == "22")

    first.performClose(nil)
    try await settle(first) { !first.isVisible && first.sheets.isEmpty }
    #expect(first.sheets.isEmpty)
    #expect(!first.isVisible)
    let fresh = try await newWindow(fileMenu)
    defer { fresh.close() }
    #expect(try sizeField(in: fresh).stringValue == "22")
    #expect(fresh.undoManager?.canUndo == false)
  }

  private func newWindow(_ menu: NSMenu) async throws -> NSWindow {
    let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
    let index = try #require(
      menu.items.firstIndex {
        $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command
      })
    menu.performActionForItem(at: index)
    let deadline = ContinuousClock.now + .seconds(10)
    while true {
      if let window = NSApp.windows.first(where: {
        $0.isVisible && $0.title == "Helvetica Neue vs. Arial"
          && !existing.contains(ObjectIdentifier($0))
      }) {
        window.contentView?.layoutSubtreeIfNeeded()
        if findSizeField(in: window) != nil { return window }
      }
      try #require(ContinuousClock.now < deadline, "No new comparison window appeared")
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  private func sizeField(in window: NSWindow) throws -> NSTextField {
    try #require(findSizeField(in: window))
  }

  private func findSizeField(in window: NSWindow) -> NSTextField? {
    guard let root = window.contentView else { return nil }
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap(descendants)
    }
    return descendants(root).compactMap { $0 as? NSTextField }.first {
      $0.placeholderString == "Size" && $0.convert($0.bounds, to: root).minX > 246
        && $0.convert($0.bounds, to: root).maxX < root.bounds.width - 246
    }
  }

  private func editCommand(modifiers: NSEvent.ModifierFlags, window: NSWindow) throws {
    let menu = try #require(NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu)
    let item = try #require(
      menu.items.first {
        $0.keyEquivalent == "z" && $0.keyEquivalentModifierMask == modifiers
      })
    let action = try #require(item.action)
    // Test hosts need not own desktop focus; send the menu action to this window.
    #expect(NSApp.sendAction(action, to: window, from: item))
  }

  private func submit(_ value: String, to field: NSTextField) {
    field.window?.makeFirstResponder(field)
    field.currentEditor()?.string = value
    (field.currentEditor() as? NSTextView)?.didChangeText()
    field.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
  }

  private func settle(_ window: NSWindow) async throws {
    try await Task.sleep(for: .milliseconds(250))
    window.contentView?.layoutSubtreeIfNeeded()
  }

  private func settle(
    _ window: NSWindow, until condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    try await settle(window)
    while !condition(), ContinuousClock.now < deadline {
      try await settle(window)
    }
    #expect(condition(), "Timed out after 10 seconds.", sourceLocation: sourceLocation)
  }
}
