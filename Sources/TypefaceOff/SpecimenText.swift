import AppKit
import SwiftUI
import TypefaceCore

struct SpecimenText: NSViewRepresentable {
  let config: FontConfiguration
  let text: String
  var highlights: Set<String> = []
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
    view.textContainerInset = NSSize(width: 24, height: 16)
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
    let key = RenderKey(config: config, text: text, highlights: highlights, side: side)
    guard context.coordinator.key != key else {
      return
    }
    context.coordinator.key = key
    let content = Self.makeContent(config: config, text: text)
    context.coordinator.position.preserveDuringUpdate {
      view.textStorage?.setAttributedString(content.text)
      view.spans = content.spans
      // Temporary drawing attributes preserve the original shaping runs and ligatures.
      view.layoutManager?.removeTemporaryAttribute(
        .foregroundColor, forCharacterRange: NSRange(location: 0, length: content.text.length))
      for span in content.spans where highlights.contains(span.glyph) && span.supported {
        view.layoutManager?.addTemporaryAttribute(
          .foregroundColor, value: side == .a ? NSColor.systemRed : NSColor.systemBlue,
          forCharacterRange: span.range)
      }
      if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
      view.setAccessibilityValue(text)
    }
  }

  static func makeContent(config: FontConfiguration, text: String) -> SampleContent {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = config.size * 0.35
    paragraph.paragraphSpacing = config.size * 0.35
    var attributes = FontRenderer.attributes(config)
    attributes[.foregroundColor] = NSColor(calibratedWhite: 0.16, alpha: 1)
    attributes[.paragraphStyle] = paragraph
    let content = NSMutableAttributedString(string: "")
    var spans: [GlyphSpan] = []
    var support: [String: Bool] = [:]
    if !FontRenderer.isAvailable(config) {
      content.append(
        NSAttributedString(
          string:
            "Font unavailable: \(config.postScriptName)\nChoose an installed font in the inspector.",
          attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.darkGray]))
    } else {
      for character in text {
        let glyph = String(character)
        let whitespace = glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let supported =
          support[glyph] ?? (whitespace || FontRenderer.supports(glyph, config: config))
        support[glyph] = supported
        var styled = attributes
        if !supported {
          styled[.font] = NSFont.systemFont(ofSize: config.size)
          styled[.foregroundColor] = NSColor.systemOrange
          styled[.toolTip] = "Unavailable: \(unicodeDescription(glyph))"
        }
        let displayed = supported ? glyph : "□"
        if !whitespace {
          spans.append(
            .init(
              range: NSRange(location: content.length, length: displayed.utf16.count), glyph: glyph,
              supported: supported))
        }
        content.append(NSAttributedString(string: displayed, attributes: styled))
      }
    }
    return SampleContent(text: content, spans: spans)
  }

  final class Coordinator {
    var key: RenderKey?
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
    let highlights: Set<String>
    let side: Side
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
      }
    }
  }
}

final class SpecimenNSTextView: NSTextView {
  var select: (String) -> Void = { _ in }
  var spans: [SpecimenText.GlyphSpan] = []

  override func mouseDown(with event: NSEvent) {
    guard let layoutManager, let textContainer else {
      super.mouseDown(with: event)
      return
    }
    let point = convert(event.locationInWindow, from: nil)
    let location = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    let index = layoutManager.characterIndex(
      for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
    if let span = spans.first(where: { NSLocationInRange(index, $0.range) }) {
      let glyphs = layoutManager.glyphRange(
        forCharacterRange: span.range, actualCharacterRange: nil)
      if layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).contains(location) {
        select(span.glyph)
        return
      }
    }
    super.mouseDown(with: event)
  }
}
