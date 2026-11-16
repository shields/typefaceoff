import AppKit
import CoreText
import SwiftUI
import TypefaceCore

struct SpecimenText: NSViewRepresentable {
  private static let warningFont =
    CTFontCreateForString(
      NSFont.systemFont(ofSize: 12) as CTFont, "⚠︎" as CFString, CFRange(location: 0, length: 2))
    as NSFont
  let config: FontConfiguration
  @ExactText var text: String
  var sample: Sample = .custom
  var inset = NSSize(width: 24, height: 31)
  var firstBaseline: (value: Double, measured: (Double) -> Void)?
  var lineFragmentPadding: CGFloat = 5
  var highlights: Set<String> = []
  var highlightKinds: [String: String] = [:]
  var side: Side = .a
  var scrollPosition: SpecimenScrollPosition?
  var select: (String) -> Void = { _ in }
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  func makeCoordinator() -> Coordinator { Coordinator(position: scrollPosition ?? .init()) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = SpecimenScrollView()
    scroll.position = context.coordinator.position
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = true
    scroll.backgroundColor = NSColor(WorkbenchStyle.paper)
    let storage = NSTextStorage()
    let layout = SpecimenLayoutManager()
    // Partial layout can move the scroll origin as earlier lines are measured.
    layout.allowsNonContiguousLayout = false
    let container = NSTextContainer()
    container.lineFragmentPadding = lineFragmentPadding
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
    view.backgroundColor = NSColor(WorkbenchStyle.paper)
    view.insertionPointColor = NSColor(WorkbenchStyle.ink)
    view.selectedTextAttributes = [
      .backgroundColor: NSColor(WorkbenchStyle.hairline).withAlphaComponent(0.5),
      .foregroundColor: NSColor(WorkbenchStyle.ink),
    ]
    let name = "\(side.fontName) specimen"
    view.axLabel = name
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
    let geometryChanged =
      coordinator.inset != inset || coordinator.firstBaseline != firstBaseline?.value
      || view.textContainer?.lineFragmentPadding != lineFragmentPadding
    guard
      contentChanged || geometryChanged || view.highlights != highlights
        || coordinator.side != side || view.underlineHighlights != differentiateWithoutColor
    else {
      return
    }
    view.renderGeneration = FuzzDiagnostics.shared.nextGeneration()
    coordinator.key = key
    coordinator.side = side
    coordinator.inset = inset
    coordinator.firstBaseline = firstBaseline?.value
    view.highlights = highlights
    view.underlineHighlights = differentiateWithoutColor
    view.highlightColor = side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue
    coordinator.position.preserveDuringUpdate {
      view.textContainer?.lineFragmentPadding = lineFragmentPadding
      if contentChanged {
        view.configureLeading(config)
        #if TYPEFACEOFF_STARTUP_BENCHMARK
          StartupDiagnostics.mark("specimen-\(side.rawValue)-start")
        #endif
        FuzzDiagnostics.shared.measure(
          "specimen-shaping", text: text, generation: view.renderGeneration
        ) {
          if spacingOnly, let storage = view.textStorage {
            Self.updateTracking(config: config, storage: storage, range: view.bodyRange)
            Self.updateLeading(config: config, storage: storage, range: view.bodyRange)
          } else {
            let content = Self.makeContent(config: config, text: text, sample: sample)
            view.textStorage?.setAttributedString(content.text)
            view.spans = content.spans
            view.bodyRange = content.bodyRange
          }
        }
        #if TYPEFACEOFF_STARTUP_BENCHMARK
          StartupDiagnostics.mark("specimen-\(side.rawValue)-ready")
        #endif
        FuzzDiagnostics.shared.measure(
          "specimen-accessibility", text: text, generation: view.renderGeneration
        ) {
          view.setAccessibilityValue(text)
        }
      }
      if contentChanged || geometryChanged {
        view.ensureSpecimenLayout()
        var alignedInset = inset
        if let firstBaseline, let layout = view.layoutManager {
          let baseline: Double
          if view.bodyRange.length > 0 {
            let glyph = layout.glyphIndexForCharacter(at: view.bodyRange.location)
            baseline =
              layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
              + layout.location(forGlyphAt: glyph).y
          } else {
            baseline = 0
          }
          alignedInset.height = max(0, firstBaseline.value - baseline)
          if coordinator.measuredBaseline != baseline {
            coordinator.measuredBaseline = baseline
            Task { @MainActor in firstBaseline.measured(baseline) }
          }
        }
        view.textContainerInset = alignedInset
        view.refreshToolTips()
      }
    }
    view.refreshHighlights()
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
            "This font is not installed.\nChoose an installed font above.",
          attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor(WorkbenchStyle.secondaryInk),
          ]))
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
        .union(italicSupport.filter { !$0.value }.keys)
      if !unavailable.isEmpty {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 16
        content.append(
          NSAttributedString(
            string:
              "⚠︎ \(unavailable.count) unavailable character\(unavailable.count == 1 ? "" : "s")\n",
            attributes: [
              .font: Self.warningFont,
              .foregroundColor: NSColor(WorkbenchStyle.ink), .paragraphStyle: paragraph,
            ]))
      }
      if !italicRanges.isEmpty && italicConfig == nil {
        content.append(
          NSAttributedString(
            string: "⚠︎ Italic unavailable: \(config.face.family)\n",
            attributes: [
              .font: Self.warningFont, .foregroundColor: NSColor(WorkbenchStyle.ink),
            ]))
      }
      bodyRange.location = content.length
      var attributes = FontRenderer.attributes(config)
      attributes[.foregroundColor] = NSColor(WorkbenchStyle.ink)
      var italicAttributes = attributes
      if let italicConfig {
        italicAttributes.merge(FontRenderer.attributes(italicConfig)) { _, new in new }
      } else {
        italicAttributes[.foregroundColor] = NSColor(WorkbenchStyle.ink)
        italicAttributes[.toolTip] = "Italic unavailable: \(config.face.family)"
      }
      var placeholders: [[Unicode.Scalar]: [NSAttributedString]] = [:]
      func placeholder(for glyph: String, emphasized: Bool) -> NSAttributedString {
        let scalars = Array(glyph.unicodeScalars)
        let style = emphasized ? 1 : 0
        if let cached = placeholders[scalars] { return cached[style] }
        let displayed =
          "[\(scalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))]"
        let tooltip = "Unavailable: \(unicodeDescription(glyph))"
        let runs = [attributes, italicAttributes].map { base in
          var styled = base
          styled[.font] = NSFont.monospacedSystemFont(
            ofSize: max(11, config.size * 0.55), weight: .medium)
          styled[.foregroundColor] = NSColor(WorkbenchStyle.ink)
          styled[.toolTip] = tooltip
          return NSAttributedString(string: displayed, attributes: styled)
        }
        placeholders[scalars] = runs
        return runs[style]
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
        let missing = supported ? nil : placeholder(for: glyph, emphasized: emphasized)
        let length = missing?.length ?? glyph.utf16.count
        if !whitespace {
          spans.append(
            .init(
              range: NSRange(location: displayedOffset, length: length),
              glyph: glyph,
              supported: supported))
        }
        displayedOffset += length
        if let missing {
          content.append(missing)
        } else {
          run.append(contentsOf: glyph)
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
    FontRenderer.automaticLeading(config)
  }

  final class Coordinator {
    var key: RenderKey?
    var side: Side?
    var inset: NSSize?
    var firstBaseline: Double?
    var measuredBaseline: Double?
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

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.config == rhs.config && lhs.sample == rhs.sample
        && lhs.text.unicodeScalars.elementsEqual(rhs.text.unicodeScalars)
    }

    func changesOnlySpacing(from previous: RenderKey) -> Bool {
      guard text.unicodeScalars.elementsEqual(previous.text.unicodeScalars),
        sample == previous.sample,
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
      if let view = documentView as? SpecimenNSTextView, contentView.bounds.width > 0 {
        view.ensureSpecimenLayout()
        view.scheduleToolTipRefresh()
      }
    }
  }

  override func reflectScrolledClipView(_ clipView: NSClipView) {
    super.reflectScrolledClipView(clipView)
    (documentView as? SpecimenNSTextView)?.scheduleToolTipRefresh()
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
  var select: (String) -> Void = { _ in }
  var highlightKinds: [String: String] = [:]
  var highlights: Set<String> = [] {
    didSet { highlightsDirty = true }
  }
  var underlineHighlights = false {
    didSet { highlightsDirty = true }
  }
  var highlightColor: NSColor = WorkbenchStyle.red {
    didSet { highlightsDirty = true }
  }
  var spans: [SpecimenText.GlyphSpan] = [] {
    didSet { highlightsDirty = true }
  }
  var bodyRange = NSRange(location: 0, length: 0)
  var renderGeneration: UInt64 = 0
  private var highlightsDirty = true
  private var highlightedCharacters: NSRange?
  private var coloredRange = NSRange(location: 0, length: 0)
  private var leadingFont: NSFont?
  private var leadingHits: [(rect: NSRect, lineY: CGFloat, glyph: Int)] = []
  private var toolTipRects: [NSRect]?
  private var toolTipRefreshScheduled = false

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

  override func draw(_ dirtyRect: NSRect) {
    FuzzDiagnostics.shared.measure(
      "specimen-drawing", text: string, generation: renderGeneration
    ) {
      refreshHighlights()
      super.draw(dirtyRect)
    }
    #if TYPEFACEOFF_STARTUP_BENCHMARK
      StartupDiagnostics.specimenDrawn(self)
    #endif
  }

  func ensureSpecimenLayout() {
    FuzzDiagnostics.shared.measure(
      "specimen-layout", text: string, generation: renderGeneration
    ) {
      if let textContainer { layoutManager?.ensureLayout(for: textContainer) }
    }
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
      layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: previous)
    }
    coloredRange = NSRange(location: 0, length: 0)
    for span in spans(intersecting: visible)
    where span.supported && highlights.contains(span.glyph) {
      // TextKit can tile while a text replacement is still updating the span list.
      guard NSMaxRange(span.range) <= textStorage.length else { continue }
      // Temporary drawing attributes preserve shaping runs and ligatures.
      layoutManager.addTemporaryAttribute(
        .foregroundColor, value: highlightColor, forCharacterRange: span.range)
      if underlineHighlights {
        layoutManager.addTemporaryAttribute(
          .underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: span.range)
      }
      coloredRange = coloredRange.length == 0 ? span.range : NSUnionRange(coloredRange, span.range)
    }
    highlightedCharacters = visible
    highlightsDirty = false
  }

  func scheduleToolTipRefresh() {
    guard !toolTipRefreshScheduled else { return }
    toolTipRefreshScheduled = true
    DispatchQueue.main.async { [weak self] in
      if let self, self.toolTipRefreshScheduled { self.refreshToolTips() }
    }
  }

  func refreshToolTips() {
    toolTipRefreshScheduled = false
    FuzzDiagnostics.shared.measure(
      "specimen-tooltips", text: string, generation: renderGeneration
    ) {
      rebuildToolTips()
    }
  }

  override func removeAllToolTips() {
    toolTipRects = nil
    super.removeAllToolTips()
  }

  private func rebuildToolTips() {
    var rects: [NSRect] = []
    defer {
      if toolTipRects != rects {
        removeAllToolTips()
        for rect in rects { addToolTip(rect, owner: self, userData: nil) }
        toolTipRects = rects
      }
    }
    leadingHits.removeAll(keepingCapacity: true)
    guard let layoutManager, let textContainer, let textStorage else { return }
    var inkBounds: [NSFont: [CGGlyph: NSRect]] = [:]
    var trackedGlyphs = Set<Int>()
    for span in spans(intersecting: visibleCharacterRange()) {
      // TextKit can tile while a text replacement is still updating the span list.
      guard NSMaxRange(span.range) <= textStorage.length else { continue }
      let glyphs = layoutManager.glyphRange(
        forCharacterRange: span.range, actualCharacterRange: nil)
      layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineRange, _ in
        let intersection = NSIntersectionRange(glyphs, lineRange)
        if self.leadingFont != nil {
          for glyph in intersection.location..<NSMaxRange(intersection)
          where trackedGlyphs.insert(glyph).inserted {
            let character = layoutManager.characterIndexForGlyph(at: glyph)
            let font = textStorage.attribute(.font, at: character, effectiveRange: nil) as! NSFont
            let cgGlyph = layoutManager.cgGlyph(at: glyph)
            let ink: NSRect
            if let cached = inkBounds[font]?[cgGlyph] {
              ink = cached
            } else {
              ink = font.boundingRect(forCGGlyph: cgGlyph)
              inkBounds[font, default: [:]][cgGlyph] = ink
            }
            let position = layoutManager.location(forGlyphAt: glyph)
            let rect = NSRect(
              x: lineRect.minX + position.x + ink.minX + self.textContainerOrigin.x,
              y: lineRect.minY + position.y - ink.maxY + self.textContainerOrigin.y,
              width: ink.width, height: ink.height
            ).intersection(self.visibleRect)
            if !rect.isEmpty {
              self.leadingHits.append((rect, lineRect.midY, glyph))
              rects.append(rect)
            }
          }
          return
        }
        let rect = layoutManager.boundingRect(
          forGlyphRange: intersection, in: textContainer
        )
        .offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
        .intersection(self.visibleRect)
        if !rect.isEmpty { rects.append(rect) }
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
