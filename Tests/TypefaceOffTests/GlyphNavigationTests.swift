import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct GlyphNavigationTests {
  @Test(arguments: [true, false])
  func glyphNavigationKeepsTheCanvasFrameFixed(comparing: Bool) async throws {
    _ = NSApplication.shared
    var comparison = Comparison(b: comparing ? .init("ArialMT") : nil)
    comparison.mode = .glyph
    let document = WorkbenchDocument(comparison: comparison)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: WorkbenchView(document: document))
    window.contentView = host
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(300))
    let canvas = try #require(descendant(GlyphDrawingView.self, in: host))
    let frame = canvas.convert(canvas.bounds, to: host)
    for glyph in ["a", "g", "@", ".", "Á", "Å", "j", "e\u{301}", "🦄", "👩‍🚀", " "] {
      document.updatePresentation { $0.selectedGlyph = glyph }
      try await Task.sleep(for: .milliseconds(60))
      #expect(canvas.convert(canvas.bounds, to: host) == frame)
    }
  }

  @Test func clickingASpecimenCharacterEnablesArrowNavigation() async throws {
    _ = NSApplication.shared
    let document = WorkbenchDocument()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: WorkbenchView(document: document))
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    try await Task.sleep(for: .milliseconds(600))
    let specimen = try #require(descendant(SpecimenNSTextView.self, in: host))
    specimen.select("a")
    try await Task.sleep(for: .milliseconds(200))
    #expect(document.comparison.selectedGlyph == "a")
    let right = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil,
        characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false,
        keyCode: 124))
    window.sendEvent(right)
    try await Task.sleep(for: .milliseconds(100))
    #expect(document.comparison.selectedGlyph != "a")
    let current = document.comparison.selectedGlyph
    let field = try #require(
      textFields(in: host).first { $0.isEditable && $0.stringValue == current })
    window.makeFirstResponder(field)
    let editor = try #require(field.currentEditor())
    editor.selectedRange = NSRange(location: 0, length: 0)
    window.sendEvent(right)
    #expect(document.comparison.selectedGlyph == current)
    #expect(editor.selectedRange.location > 0)
    let canvas = try #require(descendant(GlyphDrawingView.self, in: host))
    canvas.requestFocus(UUID())
    window.sendEvent(right)
    try await Task.sleep(for: .milliseconds(100))
    #expect(document.comparison.selectedGlyph != current)
  }

  private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let result = view as? T { return result }
    return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
  }

  private func textFields(in view: NSView) -> [NSTextField] {
    if let field = view as? NSTextField { return [field] }
    return view.subviews.flatMap { textFields(in: $0) }
  }

}
