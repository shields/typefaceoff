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

@Suite(.serialized) @MainActor struct RenderingEdgeTests {
  @Test func changingHighlightsPreservesTextStorageSelectionAndMissingGlyphs() async throws {
    let text = String(repeating: "fi a 🦄\n", count: 40)
    var config = FontConfiguration("HelveticaNeue")
    let host = WorkbenchTestHost(SpecimenText(config: config, text: text), width: 400, height: 250)
    defer { host.window.close() }
    try await host.settle()
    let specimen = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let storage = try #require(specimen.textStorage)
    let layout = try #require(specimen.layoutManager)
    let scroll = try #require(specimen.enclosingScrollView)
    let original = NSAttributedString(attributedString: storage)
    let edits = StorageEditCounter()
    storage.delegate = edits
    let missing = try #require(specimen.spans.first { $0.glyph == "🦄" })
    #expect(!missing.supported)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
    scroll.reflectScrolledClipView(scroll.contentView)
    let container = try #require(specimen.textContainer)
    let visible = layout.characterRange(
      forGlyphRange: layout.glyphRange(
        forBoundingRect: specimen.visibleRect.offsetBy(
          dx: -specimen.textContainerOrigin.x, dy: -specimen.textContainerOrigin.y),
        in: container), actualGlyphRange: nil)
    let a = try #require(specimen.spans(intersecting: visible).first { $0.glyph == "a" })
    specimen.setSelectedRange(a.range)
    let origin = scroll.contentView.bounds.origin

    for side: Side in [.a, .b] {
      host.setContent(
        SpecimenText(
          config: config, text: text, highlights: ["a", "🦄"],
          highlightKinds: ["a": "Shape"], side: side))
      try await host.settle()
      #expect(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first === specimen)
      #expect(edits.count == 0)
      #expect(storage == original)
      #expect(specimen.selectedRange() == a.range)
      #expect(scroll.contentView.bounds.origin == origin)
      #expect(
        layout.temporaryAttribute(
          .foregroundColor, atCharacterIndex: a.range.location, effectiveRange: nil) as? NSColor
          == (side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue))
      #expect(
        layout.temporaryAttribute(
          .foregroundColor, atCharacterIndex: missing.range.location, effectiveRange: nil) == nil)
    }
    host.setContent(SpecimenText(config: config, text: text))
    try await host.settle()
    #expect(edits.count == 0)
    #expect(
      layout.temporaryAttribute(
        .foregroundColor, atCharacterIndex: a.range.location, effectiveRange: nil) == nil)

    config.size = 44
    host.setContent(SpecimenText(config: config, text: text + "x"))
    try await host.settle()
    #expect(edits.count > 0)
    #expect(specimen.string.hasSuffix("x"))
    #expect(
      (storage.attribute(.font, at: a.range.location, effectiveRange: nil) as? NSFont)?.pointSize
        == 44)
  }

  @Test func clickingRenderedGlyphsSelectsTheirOriginalCharacters() async throws {
    var selected = ""
    let host = WorkbenchTestHost(
      SpecimenText(config: .init("HelveticaNeue"), text: "a🦄", select: { selected = $0 }),
      width: 400, height: 300)
    defer { host.window.close() }
    try await host.settle()
    let specimen = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let layout = try #require(specimen.layoutManager)
    let container = try #require(specimen.textContainer)
    for span in specimen.spans {
      let glyphs = layout.glyphRange(forCharacterRange: span.range, actualCharacterRange: nil)
      let bounds = layout.boundingRect(forGlyphRange: glyphs, in: container)
      let point = NSPoint(
        x: bounds.midX + specimen.textContainerOrigin.x,
        y: bounds.midY + specimen.textContainerOrigin.y)
      specimen.mouseDown(with: try mouseEvent(.leftMouseDown, view: specimen, point: point))
      #expect(selected == span.glyph)
    }
    let last = selected
    let outside = NSPoint(x: specimen.bounds.maxX - 2, y: 2)
    NSApp.postEvent(try mouseEvent(.leftMouseUp, view: specimen, point: outside), atStart: true)
    specimen.mouseDown(with: try mouseEvent(.leftMouseDown, view: specimen, point: outside))
    #expect(selected == last)
  }

  @Test func previewsWithoutSelectionHandlersRemainReadOnly() async throws {
    let content = SpecimenText(config: .init("HelveticaNeue"), text: "a")
    content.select("a")
    let host = WorkbenchTestHost(content, width: 300, height: 200)
    defer { host.window.close() }
    try await host.settle()
    let specimen = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    #expect(!specimen.isEditable)
    #expect(specimen.string == "a")
    let unattached = SpecimenNSTextView()
    unattached.select("a")
    #expect(unattached.string.isEmpty)
  }

  @Test func detachedGlyphCanvasHandlesInputAndUnavailableFonts() throws {
    let canvas = GlyphDrawingView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    canvas.draw(.zero)
    canvas.mouseDown(with: try mouseEvent(.leftMouseDown, view: canvas, point: .zero))
    let right = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}",
        isARepeat: false, keyCode: 124))
    canvas.keyDown(with: right)
    let command = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0,
        context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false,
        keyCode: 0))
    canvas.keyDown(with: command)
    #expect(canvas.acceptsFirstResponder)
    var comparison = Comparison(a: .init("TypefaceOff-Does-Not-Exist"), b: nil)
    comparison.shape = false
    comparison.spacing = true
    canvas.update(comparison)
    let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
    #expect(bitmap.pixelsWide >= 640 && bitmap.pixelsWide * 400 == bitmap.pixelsHigh * 640)
    #expect(canvas.accessibilityLabel()?.contains("Font A") == true)
  }

  @Test func scrollViewsWithoutDocumentsCanAttachAndReset() {
    let position = SpecimenScrollPosition()
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    position.attach(scroll)
    position.reset()
    #expect(scroll.contentView.bounds.origin == .zero)
    position.detach(scroll)
    let specimen = SpecimenScrollView(frame: scroll.frame)
    specimen.tile()
    #expect(specimen.contentView.bounds.size.width > 0)
  }

  @Test func verticalGuidesRemainVisibleWithSpacingHighlightsOff() throws {
    let canvas = GlyphDrawingView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    var comparison = Comparison()
    comparison.shape = true
    comparison.spacing = false
    canvas.update(comparison)
    let without = try bitmap(canvas)
    comparison.spacing = true
    canvas.update(comparison)
    #expect(try bitmap(canvas) == without)
  }

  @Test func unavailableFeaturePreviewsExposeTheUnsupportedText() async throws {
    let host = WorkbenchTestHost(
      FontPreviewText(config: .init("Missing-Preview-Font"), text: "A", size: 17), width: 200,
      height: 40)
    defer { host.window.close() }
    for (name, glyph) in [("Missing-Preview-Font", "A"), ("HelveticaNeue", "🦄")] {
      host.setContent(FontPreviewText(config: .init(name), text: glyph, size: 17))
      try await host.settle()
      let view = try #require(host.subviews.compactMap { $0 as? FontPreviewDrawingView }.first)
      #expect(view.content.string == "⚠︎ Unavailable")
      #expect(view.toolTip == "Unavailable: \(unicodeDescription(glyph))")
    }
    host.setContent(FontPreviewText(config: .init("HelveticaNeue"), text: "fi", size: 17))
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? FontPreviewDrawingView }.first)
    #expect(view.content.string == "fi" && view.toolTip == nil)
  }

  @Test func featurePreviewDrawsDifferentInkForLigatures() throws {
    let view = FontPreviewDrawingView(frame: NSRect(x: 0, y: 0, width: 90, height: 30))
    view.draw(.zero)
    var config = FontConfiguration("HelveticaNeue")
    config.features["aat.1.2"] = 3
    view.content = FontPreviewText.content(config: config, text: "fi fl")
    let before = try bitmap(view)
    config.features["aat.1.2"] = 2
    view.content = FontPreviewText.content(config: config, text: "fi fl")
    #expect(try bitmap(view) != before)
    #expect(view.accessibilityLabel() == "fi fl")
  }

  private func bitmap(_ view: NSView) throws -> Data {
    let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: image)
    return try #require(image.representation(using: .png, properties: [:]))
  }

  @Test(arguments: ["NotoSansSyriac-Regular", "TypefaceOff-Does-Not-Exist", "Skia"])
  func uncommonFontStatesStayVisible(name: String) async throws {
    let configuredName =
      name == "Skia" ? try #require(FontCatalog().preferredFace(in: name)).id : name
    var comparison = Comparison(a: .init(configuredName), b: .init("TypefaceOff-Does-Not-Exist"))
    comparison.mode = .glyph
    comparison.selectedGlyph = "ܐ"
    comparison.a.axes = [:]
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel(comparison: comparison)))
    defer { host.window.close() }
    try await host.settle()
    #expect(!(host.elements + host.hitElements).contains { $0.accessibilityLabel?() == "Match…" })
    #expect(host.window.title.hasSuffix(" vs. TypefaceOff-Does-Not-Exist (unavailable)"))
    let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
    #expect(bitmap.pixelsWide > 0)
    #expect(comparison.a.postScriptName == configuredName)
  }

  private func mouseEvent(_ type: NSEvent.EventType, view: NSView, point: NSPoint) throws -> NSEvent
  {
    try #require(
      NSEvent.mouseEvent(
        with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
        windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 1))
  }
}

@MainActor private final class StorageEditCounter: NSObject, @preconcurrency NSTextStorageDelegate {
  var count = 0

  func textStorage(
    _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange, changeInLength delta: Int
  ) {
    count += 1
  }
}
