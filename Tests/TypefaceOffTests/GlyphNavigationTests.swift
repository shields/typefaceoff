// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct GlyphNavigationTests {
  @Test func focusFeedbackFollowsTheCanvasAndWindow() async throws {
    var focused = false
    var comparison = Comparison(b: nil)
    comparison.mode = .glyph
    let window = GlyphFocusTestWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = NSHostingView(
      rootView: VStack {
        TextField("Focus probe", text: .constant(""))
        GlyphComparisonView(
          comparison: comparison, focusRequest: UUID(), searching: .constant(false),
          select: { _ in }, navigate: { _ in },
          showText: {}, focusChanged: { focused = $0 })
      })
    window.contentView = view
    window.orderFront(nil)
    try await waitUntil {
      view.layoutSubtreeIfNeeded()
      return descendant(GlyphDrawingView.self, in: view) != nil
    }
    let canvas = try #require(descendant(GlyphDrawingView.self, in: view))
    canvas.requestFocus(UUID())
    try await waitUntil { focused && canvas.hasKeyboardFocus }
    #expect(canvas.hasKeyboardFocus)
    #expect(focused)
    let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
    let field = try #require(textFields(in: view).first { $0.placeholderString == "Focus probe" })
    window.makeFirstResponder(field)
    try await waitUntil { !focused && !canvas.hasKeyboardFocus }
    #expect(!canvas.hasKeyboardFocus)
    #expect(!focused)
    canvas.requestFocus(UUID())
    try await waitUntil { focused }
    #expect(focused)
    window.setKey(false)
    try await waitUntil { !focused && !canvas.hasKeyboardFocus }
    #expect(!focused)
    #expect(!canvas.hasKeyboardFocus)
    window.setKey(true)
    try await waitUntil { focused && canvas.hasKeyboardFocus }
    #expect(focused)
    #expect(canvas.hasKeyboardFocus)
  }

  @Test(arguments: [true, false])
  func glyphNavigationKeepsTheCanvasFrameFixed(comparing: Bool) async throws {
    _ = NSApplication.shared
    var comparison = Comparison(b: comparing ? .init("ArialMT") : nil)
    comparison.mode = .glyph
    let model = WorkbenchModel(comparison: comparison)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(
      rootView: WorkbenchView(model: model).environment(\.appearsActive, true))
    window.contentView = host
    window.orderFront(nil)
    try await waitUntil {
      host.layoutSubtreeIfNeeded()
      return descendant(GlyphDrawingView.self, in: host) != nil
    }
    try await Task.sleep(for: .milliseconds(300))
    let canvas = try #require(descendant(GlyphDrawingView.self, in: host))
    let frame = canvas.convert(canvas.bounds, to: host)
    for glyph in ["a", "g", "@", ".", "Á", "Å", "j", "e\u{301}", "🦄", "👩‍🚀", " "] {
      model.updatePresentation { $0.selectedGlyph = glyph }
      try await Task.sleep(for: .milliseconds(60))
      #expect(canvas.convert(canvas.bounds, to: host) == frame)
    }
  }

  @Test func clickingASpecimenCharacterEnablesArrowNavigation() async throws {
    _ = NSApplication.shared
    let model = WorkbenchModel()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: WorkbenchView(model: model))
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    try await waitUntil {
      host.layoutSubtreeIfNeeded()
      return descendant(SpecimenNSTextView.self, in: host) != nil
    }
    let specimen = try #require(descendant(SpecimenNSTextView.self, in: host))
    specimen.select("")
    #expect(model.comparison.mode == .text)
    specimen.select("a")
    try await waitUntil {
      host.layoutSubtreeIfNeeded()
      let canvas = descendant(GlyphDrawingView.self, in: host)
      return model.comparison.mode == .glyph && canvas != nil && window.firstResponder === canvas
    }
    #expect(model.comparison.selectedGlyph == "a")
    let right = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil,
        characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false,
        keyCode: 124))
    window.sendEvent(right)
    try await waitUntil {
      host.layoutSubtreeIfNeeded()
      return model.comparison.selectedGlyph != "a"
    }
    #expect(model.comparison.selectedGlyph != "a")
    let current = model.comparison.selectedGlyph
    let frame = try #require(host.superview)
    let field = try #require(
      textFields(in: frame).first { $0.placeholderString == "Find Character" })
    field.stringValue = current
    window.makeFirstResponder(field)
    let editor = try #require(field.currentEditor())
    editor.selectedRange = NSRange(location: 0, length: 0)
    window.sendEvent(right)
    #expect(model.comparison.selectedGlyph == current)
    #expect(editor.selectedRange.location > 0)
    let canvas = try #require(descendant(GlyphDrawingView.self, in: host))
    canvas.requestFocus(UUID())
    window.sendEvent(right)
    try await waitUntil { model.comparison.selectedGlyph != current }
    #expect(model.comparison.selectedGlyph != current)
  }

  @Test(arguments: [false, true])
  func clickingTheGlyphCanvasReturnsToTheText(accessibility: Bool) async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle { descendant(SpecimenNSTextView.self, in: host.view) != nil }
    let specimen = try #require(descendant(SpecimenNSTextView.self, in: host.view))
    specimen.select("g")
    try await host.settle {
      model.comparison.mode == .glyph && descendant(GlyphDrawingView.self, in: host.view) != nil
    }
    let canvas = try #require(descendant(GlyphDrawingView.self, in: host.view))
    #expect(model.comparison.mode == .glyph)
    if accessibility {
      #expect(canvas.accessibilityPerformPress())
    } else {
      let event = try #require(
        NSEvent.mouseEvent(
          with: .leftMouseDown, location: canvas.convert(.zero, to: nil), modifierFlags: [],
          timestamp: 0, windowNumber: host.window.windowNumber, context: nil, eventNumber: 0,
          clickCount: 1, pressure: 1))
      canvas.mouseDown(with: event)
    }
    try await host.settle {
      model.comparison.mode == .text && model.comparison.selectedGlyph == "g"
        && descendant(SpecimenNSTextView.self, in: host.view) != nil
    }
    #expect(model.comparison.mode == .text)
    #expect(model.comparison.selectedGlyph == "g")
    #expect(descendant(SpecimenNSTextView.self, in: host.view) != nil)
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

/// Exercise key-window notifications even when the test runner cannot take foreground focus.
@MainActor private final class GlyphFocusTestWindow: NSWindow {
  private var key = true
  override var isKeyWindow: Bool { key }

  override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
    let editor = super.fieldEditor(createFlag, for: object)
    (editor as? NSTextView)?.enabledTextCheckingTypes = 0
    return editor
  }

  func setKey(_ value: Bool) {
    key = value
    NotificationCenter.default.post(
      name: value ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification,
      object: self)
  }
}
