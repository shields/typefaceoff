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
    let trackingOnly = coordinator.key.map { key.changesOnlyTracking(from: $0) } == true
    guard contentChanged || view.highlights != highlights || coordinator.side != side else {
      return
    }
    coordinator.key = key
    coordinator.side = side
    view.highlights = highlights
    view.highlightColor = side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue
    coordinator.position.preserveDuringUpdate {
      if contentChanged {
        #if TYPEFACEOFF_STARTUP_BENCHMARK
          StartupDiagnostics.mark("specimen-\(side.rawValue)-start")
        #endif
        if trackingOnly, let storage = view.textStorage {
          Self.updateTracking(config: config, storage: storage, range: view.bodyRange)
        } else {
          let content = Self.makeContent(config: config, text: text, sample: sample)
          view.textStorage?.setAttributedString(content.text)
          view.spans = content.spans
          view.bodyRange = content.bodyRange
        }
        #if TYPEFACEOFF_STARTUP_BENCHMARK
          StartupDiagnostics.mark("specimen-\(side.rawValue)-ready")
        #endif
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.refreshToolTips()
        view.setAccessibilityValue(text)
      }
    }
    view.refreshHighlights()
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

  final class Coordinator {
    var key: RenderKey?
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

    func changesOnlyTracking(from previous: RenderKey) -> Bool {
      guard text == previous.text, sample == previous.sample,
        config.tracking != previous.config.tracking
      else { return false }
      var unchanged = config
      unchanged.tracking = previous.config.tracking
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

final class SpecimenNSTextView: NSTextView, NSViewToolTipOwner {
  // Do not call setAccessibilityLabel or setAccessibilityIdentifier on this view: AppKit records
  // an "attribute unimplemented" error that a press which creates the view returns as -25200.
  var axLabel: String?
  var axIdentifier: String?
  var select: (String) -> Void = { _ in }
  var highlightKinds: [String: String] = [:]
  var highlights: Set<String> = [] {
    didSet { highlightsDirty = true }
  }
  var highlightColor: NSColor = WorkbenchStyle.red {
    didSet { highlightsDirty = true }
  }
  var spans: [SpecimenText.GlyphSpan] = [] {
    didSet { highlightsDirty = true }
  }
  var bodyRange = NSRange(location: 0, length: 0)
  private var highlightsDirty = true
  private var highlightedCharacters: NSRange?
  private var coloredRange = NSRange(location: 0, length: 0)

  override func accessibilityLabel() -> String? { axLabel ?? super.accessibilityLabel() }
  // AppKit's empty identifier for unnamed text views preserves label-based name matching.
  override func accessibilityIdentifier() -> String {
    axIdentifier ?? super.accessibilityIdentifier()
  }

  override func draw(_ dirtyRect: NSRect) {
    refreshHighlights()
    super.draw(dirtyRect)
    #if TYPEFACEOFF_STARTUP_BENCHMARK
      StartupDiagnostics.specimenDrawn(self)
    #endif
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    refreshHighlights()
    refreshToolTips()
  }

  func spans(intersecting range: NSRange) -> ArraySlice<SpecimenText.GlyphSpan> {
    guard range.length > 0 else { return spans[0..<0] }
    var lower = 0
    var upper = spans.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if NSMaxRange(spans[middle].range) <= range.location {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    let start = lower
    upper = spans.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if spans[middle].range.location < NSMaxRange(range) {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    return spans[start..<lower]
  }

  private func visibleCharacterRange() -> NSRange {
    guard let layoutManager, let textContainer, !visibleRect.isEmpty else {
      return NSRange(location: 0, length: 0)
    }
    let glyphs = layoutManager.glyphRange(
      forBoundingRect: visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y),
      in: textContainer)
    return layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
  }

  func refreshHighlights() {
    guard let layoutManager, let textStorage else { return }
    let visible = visibleCharacterRange()
    guard highlightsDirty || highlightedCharacters != visible else { return }
    let previous = NSIntersectionRange(
      coloredRange, NSRange(location: 0, length: textStorage.length))
    if previous.length > 0 {
      layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: previous)
    }
    coloredRange = NSRange(location: 0, length: 0)
    for span in spans(intersecting: visible)
    where span.supported && highlights.contains(span.glyph) {
      // TextKit can tile while a text replacement is still updating the span list.
      guard NSMaxRange(span.range) <= textStorage.length else { continue }
      // Temporary drawing attributes preserve shaping runs and ligatures.
      layoutManager.addTemporaryAttribute(
        .foregroundColor, value: highlightColor, forCharacterRange: span.range)
      coloredRange = coloredRange.length == 0 ? span.range : NSUnionRange(coloredRange, span.range)
    }
    highlightedCharacters = visible
    highlightsDirty = false
  }

  func refreshToolTips() {
    removeAllToolTips()
    guard let layoutManager, let textContainer, let textStorage else { return }
    for span in spans(intersecting: visibleCharacterRange()) {
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
