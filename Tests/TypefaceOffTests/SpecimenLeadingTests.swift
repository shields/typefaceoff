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
import CoreText
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct SpecimenLeadingTests {
  @Test(arguments: ["Helvetica Neue", "Arial", "Times New Roman", "Skia"], [22.0, 40.5])
  func automaticLeadingMatchesRenderedBaselineSpacing(name: String, size: Double) async throws {
    var config = FontConfiguration(try #require(FontCatalog().preferredFace(in: name)).id)
    config.size = size
    let host = WorkbenchTestHost(SpecimenText(config: config, text: "a\na"))
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let baselines = Self.baselines(try #require(view.layoutManager), range: view.bodyRange)
    try #require(baselines.count == 2)
    let automatic = SpecimenText.automaticLeading(config)
    #expect(abs(baselines[1] - baselines[0] - automatic) < 0.001)
    config.leading = 12
    #expect(SpecimenText.automaticLeading(config) == automatic)
  }

  @Test(
    arguments: [1.0, 12, 30, 30.5, 60, 200, 288], ["HelveticaNeue", "ArialMT", "TimesNewRomanPSMT"])
  func explicitLeadingSetsBaselineDistances(leading: Double, name: String) async throws {
    var config = FontConfiguration(name)
    config.leading = leading
    let text =
      String(repeating: "Ag fi words that wrap onto several lines. ", count: 4)
      + "\nAnother paragraph.\n\n🦄\nLast line."
    let host = WorkbenchTestHost(SpecimenText(config: config, text: text), width: 230, height: 400)
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let baselines = Self.baselines(try #require(view.layoutManager), range: view.bodyRange)
    #expect(baselines.count > 8)
    for (first, second) in zip(baselines, baselines.dropFirst()) {
      #expect(abs(second - first - leading) < 0.001)
    }
  }

  @Test(arguments: [NSSize.zero, NSSize(width: 24, height: 31)])
  func leadingPreservesTheFirstLineAndItsVisibleInk(inset: NSSize) async throws {
    var config = FontConfiguration("HelveticaNeue")
    let host = WorkbenchTestHost(
      SpecimenText(config: config, text: "Hamburg", inset: inset), width: 240, height: 100)
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    let baseline = try #require(Self.baselines(layout, range: view.bodyRange).first)
    let occupied = layout.usedRect(for: container)
    let inkBottom =
      baseline - FontRenderer.measure("Hamburg", config: config, size: config.size).bounds.minY
    let ink = try Self.visibleInk(view)
    #expect(ink.count > 100)
    for leading: Double? in [1, 12, 200, 288, nil] {
      config.leading = leading
      host.setContent(SpecimenText(config: config, text: "Hamburg", inset: inset))
      try await host.settle()
      #expect(Self.baselines(layout, range: view.bodyRange) == [baseline])
      #expect(layout.usedRect(for: container).height >= inkBottom)
      #expect(layout.usedRect(for: container).height <= occupied.height)
      #expect(try Self.visibleInk(view).symmetricDifference(ink).isEmpty)
    }
  }

  @Test func matchingPreviewsRemainVisibleWithExtremeLeading() async throws {
    var comparison = Comparison()
    comparison.shape = false
    comparison.spacing = false
    comparison.a.leading = 1
    comparison.b?.leading = 200
    comparison.sample = .custom
    comparison.customText = "Hamburg\nHamburg"
    comparison.calibrate()
    let model = WorkbenchModel(comparison: comparison)
    let fit = FontFitModel(load: SimilarityModelTests.fitResult)
    let host = WorkbenchTestHost(
      WorkbenchView(model: model, fit: fit, matching: true), width: 1440, height: 900)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Font B Optimize tracking")
    try await host.settle { fit.result != nil }
    let previews = host.subviews.compactMap { $0 as? SpecimenNSTextView }
    #expect(previews.count == 2)
    for preview in previews {
      #expect(preview.string == "Hamburg\nHamburg")
      let layout = try #require(preview.layoutManager)
      let baseline = try #require(Self.baselines(layout, range: preview.bodyRange).first)
      let line = CTLineCreateWithAttributedString(try #require(preview.textStorage))
      let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
      let inkTop = preview.textContainerOrigin.y + baseline - bounds.maxY
      let inkBottom = preview.textContainerOrigin.y + baseline - bounds.minY
      #expect(inkTop >= preview.visibleRect.minY)
      #expect(inkBottom <= preview.visibleRect.maxY)
      let firstLine = NSRect(
        x: 0, y: inkTop, width: min(200, preview.bounds.width), height: inkBottom - inkTop)
      #expect(try Self.visibleInk(preview, rect: firstLine).count > 100)
    }
  }

  @Test(arguments: [1.0, 12], [NSSize.zero, NSSize(width: 24, height: 31)])
  func partialRedrawAndScrollingPreserveOverflowingInk(leading: Double, inset: NSSize) async throws
  {
    var config = FontConfiguration("HelveticaNeue")
    config.leading = leading
    let host = WorkbenchTestHost(
      SpecimenText(config: config, text: "g" + String(repeating: "\n", count: 100), inset: inset),
      width: 180, height: 60)
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let layout = try #require(view.layoutManager)
    let baseline = try #require(Self.baselines(layout, range: view.bodyRange).first)
    let strip = NSRect(
      x: 0, y: view.textContainerOrigin.y + baseline, width: view.bounds.width, height: 4)
    #expect(
      layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).maxY
        < strip.minY - view.textContainerOrigin.y)
    let expected = try Self.renderedInk(view, in: strip, fullGlyphRange: true)
    #expect(!expected.isEmpty)
    #expect(try Self.renderedInk(view, in: strip) == expected)

    let scroll = try #require(view.enclosingScrollView)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: strip.minY))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await host.settle()
    #expect(view.visibleRect.minY == strip.minY)
    let visible = try Self.renderedInk(view, in: view.visibleRect, fullGlyphRange: true)
    #expect(!visible.isEmpty)
    #expect(try Self.renderedInk(view, in: view.visibleRect) == visible)
  }

  @Test(arguments: ["HelveticaNeue", "Skia", "TypefaceOff-Does-Not-Exist"])
  func leadingUpdatesPreserveEmphasisAndWarnings(name: String) {
    var config = FontConfiguration(name)
    let samples: [(String, Sample)] = [
      (Sample.reading.text, .reading), ("a\n🦄\nfi", .custom), ("", .custom), ("  \n", .custom),
    ]
    for (text, sample) in samples {
      let original = SpecimenText.makeContent(config: config, text: text, sample: sample)
      let storage = NSMutableAttributedString(attributedString: original.text)
      for leading: Double? in [32, 12, nil] {
        config.leading = leading
        SpecimenText.updateLeading(config: config, storage: storage, range: original.bodyRange)
        let fresh = SpecimenText.makeContent(config: config, text: text, sample: sample)
        #expect(storage == fresh.text)
        #expect(original.spans == fresh.spans)
        let warnings = NSRange(location: 0, length: original.bodyRange.location)
        #expect(
          storage.attributedSubstring(from: warnings)
            == original.text.attributedSubstring(from: warnings))
      }
    }
  }

  @Test func leadingEditsPreserveSelectionAndRestoreAutomaticLayout() async throws {
    var config = FontConfiguration("HelveticaNeue")
    let text = String(repeating: "fi a 🦄\n", count: 80)
    let original = SpecimenText.makeContent(config: config, text: text)
    let host = WorkbenchTestHost(SpecimenText(config: config, text: text), width: 400, height: 250)
    defer { host.window.close() }
    try await host.settle()
    let specimen = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let storage = try #require(specimen.textStorage)
    let layout = try #require(specimen.layoutManager)
    let automaticBaselines = Self.baselines(layout, range: specimen.bodyRange)
    let selected = try #require(specimen.spans.first { $0.glyph == "a" }).range
    specimen.setSelectedRange(selected)
    for leading: Double? in [40, 15, nil] {
      config.leading = leading
      host.setContent(SpecimenText(config: config, text: text))
      try await host.settle()
      #expect(specimen.textStorage === storage)
      #expect(specimen.selectedRange() == selected)
      #expect(specimen.spans == original.spans)
      #expect(storage == SpecimenText.makeContent(config: config, text: text).text)
    }
    #expect(Self.baselines(layout, range: specimen.bodyRange) == automaticBaselines)
  }

  static func baselines(_ layout: NSLayoutManager, range: NSRange) -> [Double] {
    var result: [Double] = []
    let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    layout.enumerateLineFragments(forGlyphRange: glyphs) {
      rect, _, _, range, _ in
      result.append(rect.minY + layout.location(forGlyphAt: range.location).y)
    }
    return result
  }

  private static func visibleInk(_ view: NSView, rect: NSRect? = nil) throws -> Set<Int> {
    let rect = rect ?? view.visibleRect
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: rect))
    view.cacheDisplay(in: rect, to: bitmap)
    var result = Set<Int>()
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        if color.alphaComponent > 0.5 && color.brightnessComponent < 0.5 {
          result.insert(y * bitmap.pixelsWide + x)
        }
      }
    }
    return result
  }

  private static func renderedInk(
    _ view: SpecimenNSTextView, in rect: NSRect, fullGlyphRange: Bool = false
  ) throws -> Set<Int> {
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.translateBy(x: -rect.minX, y: rect.maxY)
    context.cgContext.scaleBy(x: 1, y: -1)
    context.cgContext.clip(to: rect)
    NSColor.white.setFill()
    rect.fill()
    if fullGlyphRange {
      let layout = try #require(view.layoutManager)
      layout.drawGlyphs(
        forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs),
        at: view.textContainerOrigin)
    } else {
      view.draw(rect)
    }
    var result = Set<Int>()
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        let color = try #require(bitmap.colorAt(x: x, y: y))
        if color.brightnessComponent < 0.5 { result.insert(y * bitmap.pixelsWide + x) }
      }
    }
    return result
  }
}
