import AppKit
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct SpecimenHighlightTests {
  @Test func spanLookupIncludesPartialGraphemesAndExcludesWhitespaceGaps() {
    let view = SpecimenNSTextView()
    #expect(view.spans(intersecting: NSRange(location: 0, length: 10)).isEmpty)
    view.spans = [
      .init(range: NSRange(location: 3, length: 2), glyph: "e\u{301}", supported: true),
      .init(range: NSRange(location: 6, length: 5), glyph: "👩‍🚀", supported: true),
      .init(range: NSRange(location: 12, length: 9), glyph: "🦄", supported: false),
    ]
    for start in 0...22 {
      for length in 0...23 {
        let range = NSRange(location: start, length: length)
        let expected = view.spans.filter { NSIntersectionRange($0.range, range).length > 0 }
        #expect(Array(view.spans(intersecting: range)) == expected)
      }
    }
  }

  @Test func largeSpecimenColorsOnlyTheViewportThroughScrollsAndUpdates() async throws {
    let text = String(repeating: "fi ab e\u{301} 🦄\n", count: 10_000)
    var config = FontConfiguration("HelveticaNeue")
    var highlights: Set<String> = ["a", "e\u{301}", "🦄"]
    let host = WorkbenchTestHost(
      SpecimenText(config: config, text: text, highlights: highlights), width: 400, height: 250)
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let storage = try #require(view.textStorage)
    let original = NSAttributedString(attributedString: storage)
    let first = try #require(view.spans.first { $0.glyph == "a" })
    view.setSelectedRange(first.range)
    try expectVisibleHighlights(view, highlights: highlights, color: WorkbenchStyle.red)

    let last = try #require(view.spans.last)
    view.scrollRangeToVisible(last.range)
    try await host.settle()
    #expect(view.visibleRect.minY > 0)
    try expectVisibleHighlights(view, highlights: highlights, color: WorkbenchStyle.red)

    for next: Set<String> in [["b"], [], ["a", "b", "🦄"]] {
      highlights = next
      host.setContent(SpecimenText(config: config, text: text, highlights: highlights, side: .b))
      try await host.settle()
      try expectVisibleHighlights(view, highlights: highlights, color: WorkbenchStyle.blue)
      #expect(storage == original)
      #expect(view.selectedRange() == first.range)
    }

    view.scrollRangeToVisible(first.range)
    try await host.settle()
    try expectVisibleHighlights(view, highlights: highlights, color: WorkbenchStyle.blue)
    host.window.setContentSize(NSSize(width: 600, height: 400))
    try await host.settle()
    try expectVisibleHighlights(view, highlights: highlights, color: WorkbenchStyle.blue)

    config.tracking = 0.03
    host.setContent(SpecimenText(config: config, text: text, highlights: highlights, side: .b))
    try await host.settle()
    try expectVisibleHighlights(view, highlights: highlights, color: WorkbenchStyle.blue)

    for leading: Double? in [12, nil] {
      config.leading = leading
      host.setContent(SpecimenText(config: config, text: text, highlights: highlights, side: .b))
      try await host.settle()
      try expectVisibleHighlights(view, highlights: highlights, color: WorkbenchStyle.blue)
      #expect(view.selectedRange() == first.range)
    }

    host.setContent(SpecimenText(config: config, text: "fi a 🦄", highlights: highlights, side: .b))
    try await host.settle()
    try expectVisibleHighlights(view, highlights: highlights, color: WorkbenchStyle.blue)
    host.setContent(SpecimenText(config: config, text: "", highlights: highlights))
    try await host.settle()
    #expect(view.string.isEmpty)
  }

  @Test func glyphCacheFollowsSampleChangesAndExactUnicodeScalars() {
    var comparison = Comparison()
    comparison.sample = .custom
    comparison.customText = String(repeating: "a;", count: 50_000)
    let model = WorkbenchModel(comparison: comparison)
    #expect(model.specimenGlyphs == [["a"], [";"]])
    model.updatePresentation { $0.shape.toggle() }
    #expect(model.specimenGlyphs == [["a"], [";"]])
    model.comparison.customText = "\u{37E}"
    #expect(model.specimenGlyphs == [["\u{37E}"]])
    let scores = [GlyphDifference(glyph: ";", shape: 1, spacing: 1)]
    #expect(
      Differences.highlights(
        scores, present: model.specimenGlyphs, shape: true, spacing: true, frequency: false
      )
      .isEmpty)
    model.comparison.customText = ";"
    #expect(model.specimenGlyphs == [[";"]])
    #expect(
      Differences.highlights(
        scores, present: model.specimenGlyphs, shape: true, spacing: true, frequency: false)
        == [";"])
    model.comparison.sample = .reading
    #expect(model.specimenGlyphs == Set(Sample.reading.text.map { Array($0.unicodeScalars) }))
    model.comparison.sample = .custom
    #expect(model.specimenGlyphs == [[";"]])
    model.comparison.customText = ""
    #expect(model.specimenGlyphs.isEmpty)
  }

  private func expectVisibleHighlights(
    _ view: SpecimenNSTextView, highlights: Set<String>, color: NSColor,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    let visible = layout.characterRange(
      forGlyphRange: layout.glyphRange(
        forBoundingRect: view.visibleRect.offsetBy(
          dx: -view.textContainerOrigin.x, dy: -view.textContainerOrigin.y), in: container),
      actualGlyphRange: nil)
    var colored = 0
    for span in view.spans {
      let actual =
        layout.temporaryAttribute(
          .foregroundColor, atCharacterIndex: span.range.location, effectiveRange: nil) as? NSColor
      let expected =
        span.supported && highlights.contains(span.glyph)
        && NSIntersectionRange(span.range, visible).length > 0
      #expect(actual == (expected ? color : nil), sourceLocation: sourceLocation)
      if actual != nil { colored += 1 }
    }
    #expect(colored < 1000, sourceLocation: sourceLocation)
    if !highlights.isEmpty { #expect(colored > 0, sourceLocation: sourceLocation) }
  }
}
