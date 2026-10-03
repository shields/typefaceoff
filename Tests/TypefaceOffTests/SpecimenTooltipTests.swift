import AppKit
import CoreText
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct SpecimenTooltipTests {
  @Test(arguments: [1.0, 12, 200])
  func explicitLeadingTracksAndSelectsVisibleInk(leading: Double) async throws {
    var config = FontConfiguration("HelveticaNeue")
    config.leading = leading
    var selected = ""
    let host = WorkbenchTestHost(
      SpecimenText(config: config, text: "a\n.", select: { selected = $0 }),
      width: 400, height: 300)
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    for span in view.spans {
      let point = try inkCenter(of: span, in: view)
      expectTrackedInkTooltip(for: span, at: point, in: view)
      let event = try #require(
        NSEvent.mouseEvent(
          with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [],
          timestamp: 0, windowNumber: host.window.windowNumber, context: nil, eventNumber: 0,
          clickCount: 1, pressure: 1))
      view.mouseDown(with: event)
      #expect(selected == span.glyph)
    }
    #expect(view.view(view, stringForToolTip: 0, point: .zero, userData: nil).isEmpty)
  }

  @Test func tightLeadingKeepsLigatureCharactersIndividuallyAddressable() async throws {
    var config = FontConfiguration("HelveticaNeue")
    config.size = 44
    config.leading = 12
    let host = WorkbenchTestHost(SpecimenText(config: config, text: "fi\n."))
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let layout = try #require(view.layoutManager)
    let line = FontRenderer.line("fi", config: config, size: config.size)
    #expect(CTLineGetGlyphCount(line) == 1)
    let regions = view.trackingAreas.filter { !$0.options.contains(.inVisibleRect) }
      .map { NSStringFromRect($0.rect) }
    #expect(regions.count == Set(regions).count)
    let originalAreas = view.trackingAreas
    view.refreshToolTips()
    #expect(view.trackingAreas.elementsEqual(originalAreas, by: { $0 === $1 }))
    view.removeAllToolTips()
    view.refreshToolTips()
    #expect(view.trackingAreas.count == originalAreas.count)
    let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    let baseline = layout.location(forGlyphAt: 0)
    for (index, span) in view.spans.prefix(2).enumerated() {
      let start = CTLineGetOffsetForStringIndex(line, index, nil)
      let end = CTLineGetOffsetForStringIndex(line, index + 1, nil)
      let point = NSPoint(
        x: view.textContainerOrigin.x + baseline.x + (start + end) / 2,
        y: view.textContainerOrigin.y + baseline.y - ink.midY)
      expectTrackedInkTooltip(for: span, at: point, in: view)
    }
  }

  @Test func tightLeadingTracksVisibleOverflowAfterScrollingAndReplacement() async throws {
    var config = FontConfiguration("HelveticaNeue")
    config.leading = 12
    let host = WorkbenchTestHost(
      SpecimenText(config: config, text: String(repeating: "a\n.\n", count: 80)),
      width: 400, height: 200)
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let last = try #require(view.spans.last)
    view.scrollRangeToVisible(last.range)
    try await host.settle()
    #expect(view.visibleRect.minY > 0)
    try expectTrackedInkTooltip(for: last, at: inkCenter(of: last, in: view), in: view)
    host.setContent(SpecimenText(config: config, text: "a\n🦄"))
    try await host.settle()
    for span in view.spans {
      try expectTrackedInkTooltip(for: span, at: inkCenter(of: span, in: view), in: view)
    }
  }

  private func inkCenter(of span: SpecimenText.GlyphSpan, in view: SpecimenNSTextView) throws
    -> NSPoint
  {
    let storage = try #require(view.textStorage)
    let layout = try #require(view.layoutManager)
    let line = CTLineCreateWithAttributedString(storage.attributedSubstring(from: span.range))
    let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    let glyph = layout.glyphIndexForCharacter(at: span.range.location)
    let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    let baseline = layout.location(forGlyphAt: glyph)
    return NSPoint(
      x: view.textContainerOrigin.x + fragment.minX + baseline.x + ink.midX,
      y: view.textContainerOrigin.y + fragment.minY + baseline.y - ink.midY)
  }

  private func expectTrackedInkTooltip(
    for span: SpecimenText.GlyphSpan, at point: NSPoint, in view: SpecimenNSTextView
  ) {
    #expect(view.visibleRect.contains(point))
    #expect(
      view.trackingAreas.contains {
        !$0.options.contains(.inVisibleRect) && $0.rect.contains(point)
      })
    #expect(
      view.view(view, stringForToolTip: 0, point: point, userData: nil)
        == (span.supported ? "" : "Unavailable: ") + unicodeDescription(span.glyph))
  }

  @Test func windowRefreshesTooltipsAfterScrollingResizingAndReplacingText() async throws {
    let sample = Sample.reading
    var config = FontConfiguration("HelveticaNeue")
    let host = WorkbenchTestHost(
      SpecimenText(config: config, text: sample.text, sample: sample), width: 400, height: 200)
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    try expectTrackedTooltip(for: #require(view.spans.first), in: view)

    let last = try #require(view.spans.last)
    view.scrollRangeToVisible(last.range)
    try await host.settle()
    #expect(view.visibleRect.minY > 0)
    try expectTrackedTooltip(for: last, in: view)

    host.window.setContentSize(NSSize(width: 600, height: 250))
    try await host.settle()
    try expectTrackedTooltip(for: last, in: view)

    config.size = 40
    host.setContent(SpecimenText(config: config, text: "a fi 🦄"))
    try await host.settle()
    try expectTrackedTooltip(for: #require(view.spans.first), in: view)
    try expectTrackedTooltip(for: #require(view.spans.last), in: view)
  }

  private func expectTrackedTooltip(for span: SpecimenText.GlyphSpan, in view: SpecimenNSTextView)
    throws
  {
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    let glyphs = layout.glyphRange(forCharacterRange: span.range, actualCharacterRange: nil)
    let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
      .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    let point = NSPoint(x: rect.midX, y: rect.midY)
    #expect(view.visibleRect.contains(point))
    // The test never asks the view to refresh its tracking areas itself.
    let areas = view.trackingAreas.filter { !$0.options.contains(.inVisibleRect) }
    #expect(areas.contains { $0.rect.contains(point) })
    #expect(
      view.view(view, stringForToolTip: 0, point: point, userData: nil)
        == (span.supported ? "" : "Unavailable: ") + unicodeDescription(span.glyph))
  }

  @Test func fullChapterTracksOnlyVisibleCharactersAndRefreshesAfterScrolling() throws {
    let sample = Sample.reading
    let content = SpecimenText.makeContent(
      config: .init("HelveticaNeue"), text: sample.text, sample: sample)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    let view = SpecimenNSTextView(frame: scroll.bounds)
    scroll.documentView = view
    view.textStorage?.setAttributedString(content.text)
    view.spans = content.spans
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    container.containerSize = NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
    layout.ensureLayout(for: container)
    view.setFrameSize(NSSize(width: 500, height: layout.usedRect(for: container).maxY + 20))
    view.updateTrackingAreas()
    // NSTextView also installs its own tracking areas for the whole visible rectangle.
    let initial = view.trackingAreas.filter { !$0.options.contains(.inVisibleRect) }
    #expect(!initial.isEmpty)
    #expect(initial.count < content.spans.count / 4)

    scroll.contentView.scroll(to: NSPoint(x: 0, y: view.bounds.height - 300))
    view.updateTrackingAreas()
    let scrolled = view.trackingAreas.filter { !$0.options.contains(.inVisibleRect) }
    #expect(!scrolled.isEmpty)
    #expect(scrolled.count < content.spans.count / 4)
    let last = try #require(content.spans.last)
    let glyphs = layout.glyphRange(forCharacterRange: last.range, actualCharacterRange: nil)
    let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
      .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    #expect(view.visibleRect.intersects(rect))
    #expect(
      view.view(
        view, stringForToolTip: 0, point: NSPoint(x: rect.midX, y: rect.midY), userData: nil)
        == unicodeDescription(last.glyph))
    #expect(view.textStorage == content.text)
  }

  @Test func tooltipsIdentifyDifferencesAndMissingGraphemesWithoutChangingShaping() throws {
    let content = SpecimenText.makeContent(config: .init("HelveticaNeue"), text: "fi a g 🦄")
    let view = SpecimenNSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    view.textStorage?.setAttributedString(content.text)
    view.spans = content.spans
    view.highlightKinds = ["g": "Shape + Spacing"]
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    layout.ensureLayout(for: container)
    view.refreshToolTips()
    for glyph in ["a", "g", "🦄"] {
      let span = try #require(content.spans.first { $0.glyph == glyph })
      let range = layout.glyphRange(forCharacterRange: span.range, actualCharacterRange: nil)
      let rect = layout.boundingRect(forGlyphRange: range, in: container)
      let point = NSPoint(
        x: view.textContainerOrigin.x + rect.midX, y: view.textContainerOrigin.y + rect.midY)
      let tooltip = view.view(view, stringForToolTip: 0, point: point, userData: nil)
      #expect(tooltip.contains(unicodeDescription(glyph)))
      if glyph == "a" {
        #expect(tooltip == unicodeDescription(glyph))
      } else {
        #expect(tooltip.contains(glyph == "g" ? "Shape + Spacing" : "Unavailable"))
      }
    }
    #expect(view.textStorage == content.text)
    let f = try #require(content.spans.first { $0.glyph == "f" })
    let i = try #require(content.spans.first { $0.glyph == "i" })
    let ligature = content.text.attributedSubstring(from: NSUnionRange(f.range, i.range))
    #expect(CTLineGetGlyphCount(CTLineCreateWithAttributedString(ligature)) == 1)
    view.textStorage?.setAttributedString(NSAttributedString(string: ""))
    view.refreshToolTips()
    #expect(view.string.isEmpty)
  }

  @Test func tooltipRefreshHandlesADetachedTextStorage() {
    let storage = NSTextStorage(string: "a")
    let layout = NSLayoutManager()
    let container = NSTextContainer()
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    let view = SpecimenNSTextView(frame: .zero, textContainer: container)
    view.spans = [.init(range: NSRange(location: 0, length: 1), glyph: "a", supported: true)]
    storage.removeLayoutManager(layout)
    #expect(view.textStorage == nil)
    view.refreshToolTips()
    #expect(view.spans.count == 1)
  }

  @Test func reusedTooltipRegionsDescribeTheCurrentScalarSequence() throws {
    let view = SpecimenNSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    var originalRects: [NSRect]?
    for text in ["\u{00E9}", "e\u{0301}"] {
      let content = SpecimenText.makeContent(config: .init("HelveticaNeue"), text: text)
      view.textStorage?.setAttributedString(content.text)
      view.spans = content.spans
      layout.ensureLayout(for: container)
      view.refreshToolTips()
      let rects = view.trackingAreas.map(\.rect)
      if let originalRects {
        #expect(rects == originalRects)
      } else {
        originalRects = rects
      }
      try expectTrackedTooltip(for: #require(view.spans.first), in: view)
    }
  }
}
