import AppKit
import CoreText
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
  var accessibilityName: String?
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
    let layout = SpecimenLayoutManager()
    // Partial layout can move the scroll origin as earlier lines are measured.
    layout.allowsNonContiguousLayout = false
    let container = NSTextContainer()
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    let view = SpecimenNSTextView(frame: .zero, textContainer: container)
    layout.delegate = view
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
    view.axLabel = "\(side.fontName) specimen"
    let name = accessibilityName ?? "\(side.fontName) specimen"
    if accessibilityName != nil { view.axIdentifier = name }
    scroll.setAccessibilityIdentifier("\(name) scroll area")
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
    let spacingOnly = coordinator.key.map { key.changesOnlySpacing(from: $0) } == true
    guard contentChanged || coordinator.highlights != highlights || coordinator.side != side else {
      return
    }
    coordinator.key = key
    coordinator.highlights = highlights
    coordinator.side = side
    coordinator.position.preserveDuringUpdate {
      if contentChanged {
        view.configureLeading(config)
        #if TYPEFACEOFF_STARTUP_BENCHMARK
          StartupDiagnostics.mark("specimen-\(side.rawValue)-start")
        #endif
        if spacingOnly, let storage = view.textStorage {
          Self.updateTracking(config: config, storage: storage, range: view.bodyRange)
          Self.updateLeading(config: config, storage: storage, range: view.bodyRange)
        } else {
          let content = Self.makeContent(config: config, text: text, sample: sample)
          view.textStorage?.setAttributedString(content.text)
          view.spans = content.spans
          view.bodyRange = content.bodyRange
        }
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
    var bodyRange = NSRange(location: 0, length: 0)
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
      bodyRange.location = content.length
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
      var displayedOffset = content.length
      var run = ""
      var runEmphasized = false
      // Append whole shaping runs. Building an attributed string for every character in the
      // chapter repeatedly bridges the same attributes and mutates Foundation's run storage.
      func flushRun() {
        guard !run.isEmpty else { return }
        content.append(
          NSAttributedString(
            string: run, attributes: runEmphasized ? italicAttributes : attributes))
        run.removeAll(keepingCapacity: true)
      }
      for character in text {
        let glyph = String(character)
        let emphasized = italicLocations.contains(sourceOffset)
        sourceOffset += glyph.utf16.count
        let whitespace = glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Every non-whitespace character was checked before constructing the specimen.
        let glyphSupport = emphasized && italicConfig != nil ? italicSupport : support
        let supported = whitespace || glyphSupport[glyph] == true
        if !supported || emphasized != runEmphasized {
          flushRun()
          runEmphasized = emphasized
        }
        let displayed =
          supported
          ? glyph
          : "[\(glyph.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))]"
        if !whitespace {
          spans.append(
            .init(
              range: NSRange(location: displayedOffset, length: displayed.utf16.count),
              glyph: glyph,
              supported: supported))
        }
        displayedOffset += displayed.utf16.count
        if supported {
          run.append(contentsOf: displayed)
        } else {
          var styled = emphasized ? italicAttributes : attributes
          styled[.font] = NSFont.monospacedSystemFont(
            ofSize: max(11, config.size * 0.55), weight: .medium)
          styled[.foregroundColor] = NSColor.systemOrange
          styled[.toolTip] = "Unavailable: \(unicodeDescription(glyph))"
          content.append(NSAttributedString(string: displayed, attributes: styled))
        }
      }
      flushRun()
      bodyRange.length = content.length - bodyRange.location
      updateLeading(config: config, storage: content, range: bodyRange)
    }
    return SampleContent(text: content, spans: spans, bodyRange: bodyRange)
  }

  static func updateTracking(
    config: FontConfiguration, storage: NSMutableAttributedString, range: NSRange
  ) {
    guard range.length > 0 else { return }
    let attribute = NSAttributedString.Key(kCTTrackingAttributeName as String)
    storage.beginEditing()
    if config.tracking == 0 {
      storage.removeAttribute(attribute, range: range)
    } else {
      storage.addAttribute(attribute, value: config.tracking * config.size, range: range)
    }
    storage.endEditing()
  }

  static func updateLeading(
    config: FontConfiguration, storage: NSMutableAttributedString, range: NSRange
  ) {
    guard range.length > 0 else { return }
    if let leading = config.leading {
      let paragraph = NSMutableParagraphStyle()
      paragraph.minimumLineHeight = leading
      paragraph.maximumLineHeight = leading
      storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
    } else {
      storage.removeAttribute(.paragraphStyle, range: range)
    }
  }

  static func automaticLeading(_ config: FontConfiguration) -> Double {
    // Empty lines round their heights; spaces preserve fractional baseline spacing.
    let storage = NSTextStorage(string: " \n ", attributes: FontRenderer.attributes(config))
    let layout = NSLayoutManager()
    let container = NSTextContainer(
      size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    layout.ensureLayout(for: container)
    let glyph = layout.glyphIndexForCharacter(at: 2)
    return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
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
    let bodyRange: NSRange
  }
  struct GlyphSpan: Equatable {
    let range: NSRange
    let glyph: String
    let supported: Bool
  }

  struct RenderKey: Equatable {
    let config: FontConfiguration
    let text: String
    let sample: Sample

    func changesOnlySpacing(from previous: RenderKey) -> Bool {
      guard text == previous.text, sample == previous.sample,
        config.tracking != previous.config.tracking || config.leading != previous.config.leading
      else { return false }
      var unchanged = config
      unchanged.tracking = previous.config.tracking
      unchanged.leading = previous.config.leading
      return unchanged == previous.config
    }
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
        // AppKit calls updateTrackingAreas after geometry changes. Rebuilding tooltips
        // here repeats that work for every intermediate tile during window layout.
      }
    }
  }
}

final class SpecimenLayoutManager: NSLayoutManager {
  var glyphOverflow: CGFloat = 0

  override func glyphRange(forBoundingRect bounds: NSRect, in container: NSTextContainer) -> NSRange
  {
    // Tight line fragments can end above their glyphs' visible descenders.
    super.glyphRange(forBoundingRect: bounds.insetBy(dx: 0, dy: -glyphOverflow), in: container)
  }
}

final class SpecimenNSTextView: NSTextView, NSViewToolTipOwner,
  @preconcurrency NSLayoutManagerDelegate
{
  // Do not call setAccessibilityLabel or setAccessibilityIdentifier on this view: AppKit records
  // an "attribute unimplemented" error that a press which creates the view returns as -25200.
  var axLabel: String?
  var axIdentifier: String?
  var select: (String) -> Void = { _ in }
  var highlightKinds: [String: String] = [:]
  var spans: [SpecimenText.GlyphSpan] = []
  var bodyRange = NSRange(location: 0, length: 0)
  private var leadingFont: NSFont?
  private var leadingHits: [(rect: NSRect, lineY: CGFloat, glyph: Int)] = []

  func configureLeading(_ config: FontConfiguration) {
    leadingFont = config.leading.map { _ in FontRenderer.font(config) as NSFont }
    layoutManager?.usesFontLeading = config.leading == nil
    if let layout = layoutManager as? SpecimenLayoutManager {
      layout.glyphOverflow = leadingFont.map { layout.defaultLineHeight(for: $0) } ?? 0
    }
  }

  func layoutManager(
    _ layoutManager: NSLayoutManager,
    shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
    lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
    baselineOffset: UnsafeMutablePointer<CGFloat>,
    in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange
  ) -> Bool {
    guard let leadingFont,
      NSLocationInRange(layoutManager.characterIndexForGlyph(at: glyphRange.location), bodyRange)
    else { return false }
    // Placeholder and italic runs must share the selected font's baseline on every line.
    baselineOffset.pointee = layoutManager.defaultBaselineOffset(for: leadingFont)
    // The final line needs its full ink height even when baselines overlap.
    lineFragmentUsedRect.pointee.size.height = layoutManager.defaultLineHeight(for: leadingFont)
    return true
  }

  override func accessibilityLabel() -> String? { axLabel ?? super.accessibilityLabel() }
  // AppKit's empty identifier for unnamed text views preserves label-based name matching.
  override func accessibilityIdentifier() -> String {
    axIdentifier ?? super.accessibilityIdentifier()
  }

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
    leadingHits.removeAll(keepingCapacity: true)
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
      layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineRange, _ in
        let intersection = NSIntersectionRange(glyphs, lineRange)
        if self.leadingFont != nil {
          for glyph in intersection.location..<NSMaxRange(intersection) {
            let character = layoutManager.characterIndexForGlyph(at: glyph)
            let font = textStorage.attribute(.font, at: character, effectiveRange: nil) as! NSFont
            let ink = font.boundingRect(forCGGlyph: layoutManager.cgGlyph(at: glyph))
            let position = layoutManager.location(forGlyphAt: glyph)
            let rect = NSRect(
              x: lineRect.minX + position.x + ink.minX + self.textContainerOrigin.x,
              y: lineRect.minY + position.y - ink.maxY + self.textContainerOrigin.y,
              width: ink.width, height: ink.height
            ).intersection(self.visibleRect)
            if !rect.isEmpty {
              self.leadingHits.append((rect, lineRect.midY, glyph))
              self.addToolTip(rect, owner: self, userData: nil)
            }
          }
          return
        }
        let rect = layoutManager.boundingRect(
          forGlyphRange: intersection, in: textContainer
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
    var location = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    if leadingFont != nil {
      guard let hit = leadingHits.last(where: { $0.rect.contains(point) }) else { return nil }
      // Overlapping ink can lie outside its line fragment; keep TextKit's horizontal caret mapping.
      location.y = hit.lineY
      let index = layoutManager.characterIndex(
        for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
      let characters = layoutManager.characterRange(
        forGlyphRange: NSRange(location: hit.glyph, length: 1), actualGlyphRange: nil)
      let character = min(max(index, characters.location), NSMaxRange(characters) - 1)
      return spans.first { NSLocationInRange(character, $0.range) }
    }
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
