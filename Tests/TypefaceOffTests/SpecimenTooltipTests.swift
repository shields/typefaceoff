import AppKit
import CoreText
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct SpecimenTooltipTests {
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
