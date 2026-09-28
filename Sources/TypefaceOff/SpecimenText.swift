import AppKit
import SwiftUI
import TypefaceCore

struct SpecimenText: NSViewRepresentable {
  let config: FontConfiguration
  let text: String
  var sample: Sample = .custom
  var inset = NSSize(width: 24, height: 31)
  var highlights: Set<String> = []
  var highlightKinds: [String: String] = [:]
  var side: Side = .a
  var scrollPosition: SpecimenScrollPosition?
  var select: (String) -> Void = { _ in }

  func makeCoordinator() -> Coordinator { Coordinator(position: scrollPosition ?? .init()) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = SpecimenScrollView()
    scroll.position = context.coordinator.position
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = true
    scroll.backgroundColor = .white
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    // Partial layout can move the scroll origin as earlier lines are measured.
    layout.allowsNonContiguousLayout = false
    let container = NSTextContainer()
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    let view = SpecimenNSTextView(frame: .zero, textContainer: container)
    view.isEditable = false
    view.isSelectable = true
    view.isRichText = true
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    view.textContainer?.widthTracksTextView = true
    view.textContainerInset = inset
    view.backgroundColor = .white
    view.setAccessibilityLabel("Font \(side.rawValue.uppercased()) specimen")
    scroll.documentView = view
    context.coordinator.position.attach(scroll)
    return scroll
  }

  static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
    coordinator.position.detach(scroll)
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let view = scroll.documentView as? SpecimenNSTextView else { return }
    view.select = select
    view.highlightKinds = highlightKinds
    let coordinator = context.coordinator
    let key = RenderKey(config: config, text: text, sample: sample)
    let contentChanged = coordinator.key != key
    guard contentChanged || coordinator.highlights != highlights || coordinator.side != side else {
      return
    }
    coordinator.key = key
    coordinator.highlights = highlights
    coordinator.side = side
    coordinator.position.preserveDuringUpdate {
      if contentChanged {
        #if TYPEFACEOFF_STARTUP_BENCHMARK
          StartupDiagnostics.mark("specimen-\(side.rawValue)-start")
        #endif
        let content = Self.makeContent(config: config, text: text, sample: sample)
        view.textStorage?.setAttributedString(content.text)
        view.spans = content.spans
        #if TYPEFACEOFF_STARTUP_BENCHMARK
          StartupDiagnostics.mark("specimen-\(side.rawValue)-ready")
        #endif
      }
      // Temporary drawing attributes preserve the original shaping runs and ligatures.
      // Ranking updates change only these attributes; rebuilding the specimen also reshapes
      // every unavailable-character placeholder and can block the main thread for a second.
      view.layoutManager?.removeTemporaryAttribute(
        .foregroundColor,
        forCharacterRange: NSRange(location: 0, length: view.string.utf16.count))
      for span in view.spans where highlights.contains(span.glyph) && span.supported {
        view.layoutManager?.addTemporaryAttribute(
          .foregroundColor, value: side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue,
          forCharacterRange: span.range)
      }
      if contentChanged {
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.refreshToolTips()
        view.setAccessibilityValue(text)
      }
    }
    FuzzDiagnostics.shared.rendered("specimen")
  }

  static func makeContent(config: FontConfiguration, text: String, sample: Sample = .custom)
    -> SampleContent
  {
    let content = NSMutableAttributedString(string: "")
    var spans: [GlyphSpan] = []
    var support: [String: Bool] = [:]
    var italicSupport: [String: Bool] = [:]
    if !FontRenderer.isAvailable(config) {
      content.append(
        NSAttributedString(
          string:
            "Font unavailable: \(config.postScriptName)\nChoose an installed font in the inspector.",
          attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.darkGray]))
    } else {
      let italicRanges = text == sample.text ? sample.italicRanges : []
      var italicLocations = IndexSet()
      for range in italicRanges {
        italicLocations.insert(integersIn: range.location..<NSMaxRange(range))
      }
      let italicConfig = italicRanges.isEmpty ? nil : FontRenderer.italicConfiguration(config)
      for glyph in Set(text.map(String.init))
      where !glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        support[glyph] = FontRenderer.supports(glyph, config: config)
      }
      if let italicConfig {
        let italicText = italicRanges.map { (text as NSString).substring(with: $0) }.joined()
        for glyph in Set(italicText.map(String.init))
        where !glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          italicSupport[glyph] = FontRenderer.supports(glyph, config: italicConfig)
        }
      }
      let unavailable = Set(support.filter { !$0.value }.keys)
        .union(italicSupport.filter { !$0.value }.keys).count
      if unavailable > 0 {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 16
        content.append(
          NSAttributedString(
            string: "\(unavailable) unavailable character\(unavailable == 1 ? "" : "s")\n",
            attributes: [
              .font: NSFont.systemFont(ofSize: 12),
              .foregroundColor: NSColor.systemOrange, .paragraphStyle: paragraph,
            ]))
      }
      if !italicRanges.isEmpty && italicConfig == nil {
        content.append(
          NSAttributedString(
            string: "Italic unavailable: \(config.face.family)\n",
            attributes: [
              .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.systemOrange,
            ]))
      }
      var attributes = FontRenderer.attributes(config)
      attributes[.foregroundColor] = NSColor(calibratedWhite: 0.16, alpha: 1)
      var italicAttributes = attributes
      if let italicConfig {
        italicAttributes.merge(FontRenderer.attributes(italicConfig)) { _, new in new }
      } else {
        italicAttributes[.foregroundColor] = NSColor.systemOrange
        italicAttributes[.toolTip] = "Italic unavailable: \(config.face.family)"
      }
      var sourceOffset = 0
      for character in text {
        let glyph = String(character)
        let emphasized = italicLocations.contains(sourceOffset)
        sourceOffset += glyph.utf16.count
        let whitespace = glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Every non-whitespace character was checked before constructing the specimen.
        let glyphSupport = emphasized && italicConfig != nil ? italicSupport : support
        let supported = whitespace || glyphSupport[glyph] == true
        var styled = emphasized ? italicAttributes : attributes
        if !supported {
          styled[.font] = NSFont.monospacedSystemFont(
            ofSize: max(11, config.size * 0.55), weight: .medium)
          styled[.foregroundColor] = NSColor.systemOrange
          styled[.toolTip] = "Unavailable: \(unicodeDescription(glyph))"
        }
        let displayed =
          supported
          ? glyph
          : "[\(glyph.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))]"
        if !whitespace {
          spans.append(
            .init(
              range: NSRange(location: content.length, length: displayed.utf16.count),
              glyph: glyph,
              supported: supported))
        }
        content.append(NSAttributedString(string: displayed, attributes: styled))
      }
    }
    return SampleContent(text: content, spans: spans)
  }

  final class Coordinator {
    var key: RenderKey?
    var highlights: Set<String> = []
    var side: Side?
    let position: SpecimenScrollPosition
    init(position: SpecimenScrollPosition) { self.position = position }
  }

  struct SampleContent {
    let text: NSAttributedString
    let spans: [GlyphSpan]
  }
  struct GlyphSpan {
    let range: NSRange
    let glyph: String
    let supported: Bool
  }

  struct RenderKey: Equatable {
    let config: FontConfiguration
    let text: String
    let sample: Sample
  }
}

final class SpecimenScrollView: NSScrollView {
  weak var position: SpecimenScrollPosition?

  override func tile() {
    guard let position else {
      super.tile()
      return
    }
    // TextKit may adjust the origin while reflowing. Restore only after layout finishes.
    position.preserveDuringUpdate {
      super.tile()
      if let view = documentView as? NSTextView, let container = view.textContainer,
        contentView.bounds.width > 0
      {
        view.layoutManager?.ensureLayout(for: container)
        (view as? SpecimenNSTextView)?.refreshToolTips()
      }
    }
  }
}

final class SpecimenNSTextView: NSTextView, NSViewToolTipOwner {
  var select: (String) -> Void = { _ in }
  var highlightKinds: [String: String] = [:]
  var spans: [SpecimenText.GlyphSpan] = []

  #if TYPEFACEOFF_STARTUP_BENCHMARK
    override func draw(_ dirtyRect: NSRect) {
      super.draw(dirtyRect)
      StartupDiagnostics.specimenDrawn(self)
    }
  #endif

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    refreshToolTips()
  }

  func refreshToolTips() {
    removeAllToolTips()
    guard let layoutManager, let textContainer, let textStorage else { return }
    // A full chapter has thousands of glyphs. Track only the visible characters;
    // AppKit refreshes tracking areas when scrolling changes the visible rectangle.
    let visibleGlyphs = layoutManager.glyphRange(
      forBoundingRect: visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y),
      in: textContainer)
    let visibleCharacters = layoutManager.characterRange(
      forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
    for span in spans where NSIntersectionRange(span.range, visibleCharacters).length > 0 {
      // TextKit can tile while a text replacement is still updating the span list.
      guard NSMaxRange(span.range) <= textStorage.length else { continue }
      let glyphs = layoutManager.glyphRange(
        forCharacterRange: span.range, actualCharacterRange: nil)
      layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, lineRange, _ in
        let rect = layoutManager.boundingRect(
          forGlyphRange: NSIntersectionRange(glyphs, lineRange), in: textContainer
        )
        .offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
        .intersection(self.visibleRect)
        if !rect.isEmpty { self.addToolTip(rect, owner: self, userData: nil) }
      }
    }
  }

  func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
    userData data: UnsafeMutableRawPointer?
  ) -> String {
    guard let span = span(at: point) else { return "" }
    let name = unicodeDescription(span.glyph)
    if !span.supported { return "Unavailable: \(name)" }
    return highlightKinds[span.glyph].map { "\(name) · \($0)" } ?? name
  }

  override func mouseDown(with event: NSEvent) {
    if let span = span(at: convert(event.locationInWindow, from: nil)) {
      select(span.glyph)
    } else {
      super.mouseDown(with: event)
    }
  }

  private func span(at point: NSPoint) -> SpecimenText.GlyphSpan? {
    guard let layoutManager, let textContainer else { return nil }
    let location = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    let index = layoutManager.characterIndex(
      for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
    if let span = spans.first(where: { NSLocationInRange(index, $0.range) }) {
      let glyphs = layoutManager.glyphRange(
        forCharacterRange: span.range, actualCharacterRange: nil)
      if layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).contains(location) {
        return span
      }
    }
    return nil
  }
}
