import AppKit
import CoreText
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct SpecimenTooltipTests {
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
}
