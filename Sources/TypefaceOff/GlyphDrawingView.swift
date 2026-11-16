import AppKit
import CoreText
import TypefaceCore

final class GlyphDrawingView: NSView {
  var differentiateWithoutColor = false
  var navigate: (Int) -> Void = { _ in }
  var showText: () -> Void = {}
  var focusChanged: (Bool) -> Void = { _ in }
  private var focusRequest: UUID?
  private var comparison = Comparison()
  private var renderGeneration: UInt64 = 0
  private var overlayCache: (key: OverlayKey, outline: GlyphOverlayOutline?)?
  private var dragLocation: NSPoint?

  var layout: GlyphLayout {
    GlyphRendering.layout(comparison, width: bounds.width * 2 + 64, height: bounds.height)
  }

  var figures: [GlyphFigure] {
    let layout = layout
    return [Side.a, .b].map { side in
      let config = comparison[side]
      return GlyphFigure(
        config: config, glyph: comparison.selectedGlyph,
        size: layout.overlaySize * (config?.size ?? comparison.a.size) / comparison.a.size,
        x: layout.overlayOrigin, baseline: bounds.height - layout.baseline,
        alignInk: !(comparison.spacing && !comparison.shape))
    }
  }

  override var acceptsFirstResponder: Bool { true }

  var hasKeyboardFocus: Bool {
    window?.isKeyWindow == true && window?.firstResponder === self
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    updateFocusState()
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    let accepted = super.resignFirstResponder()
    updateFocusState()
    return accepted
  }

  func requestFocus(_ request: UUID) {
    guard focusRequest != request else { return }
    focusRequest = request
    window?.makeFirstResponder(self)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    if let window {
      for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
        NotificationCenter.default.addObserver(
          self, selector: #selector(updateFocusState), name: name, object: window)
      }
    }
    if focusRequest != nil { window?.makeFirstResponder(self) }
    updateFocusState()
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func updateFocusState() {
    // First-responder callbacks run before the window finishes changing responders.
    // Defer the SwiftUI state update until both AppKit and view updates finish.
    Task { @MainActor [weak self] in
      guard let self else { return }
      focusChanged(hasKeyboardFocus)
    }
  }

  override func mouseDown(with event: NSEvent) {
    if let scroll = enclosingScrollView, scroll.magnification > 1 {
      window?.makeFirstResponder(self)
      dragLocation = event.locationInWindow
      NSCursor.closedHand.set()
    } else {
      showText()
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let previous = dragLocation, let scroll = enclosingScrollView as? GlyphScrollView else {
      return
    }
    let current = event.locationInWindow
    scroll.pan(by: NSSize(width: previous.x - current.x, height: previous.y - current.y))
    dragLocation = current
  }

  override func mouseUp(with event: NSEvent) {
    dragLocation = nil
    window?.invalidateCursorRects(for: self)
  }

  override func resetCursorRects() {
    if let scroll = enclosingScrollView, scroll.magnification > 1 {
      addCursorRect(visibleRect, cursor: .openHand)
    }
  }

  override func accessibilityPerformPress() -> Bool {
    if let scroll = enclosingScrollView, scroll.magnification > 1 {
      window?.makeFirstResponder(self)
    } else {
      showText()
    }
    return true
  }

  override func keyDown(with event: NSEvent) {
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
      [123, 124].contains(event.keyCode)
    else {
      super.keyDown(with: event)
      return
    }
    navigate(event.keyCode == 123 ? -1 : 1)
  }

  func update(_ value: Comparison) {
    renderGeneration = FuzzDiagnostics.shared.nextGeneration()
    comparison = value
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityIdentifier("Glyph canvas")
    let installedA = FontRenderer.isAvailable(value.a)
    let installedB = value.b.map(FontRenderer.isAvailable) == true
    var description = "\(unicodeDescription(value.selectedGlyph)). "
    if installedA && installedB {
      description += "Font A in red, font B in blue, shared ink in black."
    } else {
      description += installedA ? "Font A." : installedB ? "Font B." : "No installed fonts."
    }
    for side in [Side.a, .b] {
      if let config = value[side] {
        if !FontRenderer.isAvailable(config) {
          description += " \(side.fontName) is not installed."
        } else if !FontRenderer.supports(value.selectedGlyph, config: config) {
          description += " Character unavailable in \(side.fontName)."
        }
      }
    }
    setAccessibilityLabel(description)
    setAccessibilityHelp(
      "Scroll the mouse wheel or pinch to zoom. When zoomed, drag or use two fingers to pan. "
        + "At 100%, click to return to text. Use Left Arrow and Right Arrow to inspect characters.")
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    FuzzDiagnostics.shared.measure(
      "glyph-drawing", text: comparison.selectedGlyph, generation: renderGeneration
    ) {
      drawGlyph(dirtyRect)
    }
  }

  private func drawGlyph(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 0, bounds.height > 0
    else { return }
    NSColor(WorkbenchStyle.paper).setFill()
    bounds.fill()
    let figures = figures
    let baseline = bounds.height - layout.baseline
    FuzzDiagnostics.shared.glyphGeometry(
      view: String(ObjectIdentifier(self).hashValue),
      context:
        "\(comparison.a.hashValue):\(comparison.b?.hashValue ?? 0):\(bounds.width):\(bounds.height)",
      glyph: comparison.selectedScalars, baseline: baseline)
    let comparing = figures.allSatisfy(\.installed)
    let zoom = enclosingScrollView?.magnification ?? 1
    let rect = bounds.intersection(visibleRect).intersection(dirtyRect)
    guard !rect.isEmpty else { return }
    let key = OverlayKey(comparison: comparison, size: bounds.size)
    if overlayCache?.key != key {
      let empty = CTLineCreateWithAttributedString(NSAttributedString(string: ""))
      overlayCache = (
        key,
        GlyphOverlayOutline(
          a: figures[0].line ?? empty, b: figures[1].line ?? empty,
          origins: figures.map(\.origin))
      )
    }
    if let outline = overlayCache?.outline {
      context.saveGState()
      context.clip(to: rect)
      let ink = NSColor(WorkbenchStyle.ink).cgColor
      outline.draw(
        in: context, red: comparing ? WorkbenchStyle.red.cgColor : ink,
        blue: comparing ? WorkbenchStyle.blue.cgColor : ink,
        differentiateWithoutColor: differentiateWithoutColor && comparing, scale: zoom)
      context.restoreGState()
    } else {
      let scale = (window?.backingScaleFactor ?? 2) * (enclosingScrollView?.magnification ?? 1)
      let width = max(1, Int(ceil(rect.width * scale)))
      let height = max(1, Int(ceil(rect.height * scale)))
      let masks = figures.map { figure in
        if let config = figure.config, figure.line != nil {
          return FontRenderer.mask(
            comparison.selectedGlyph, config: config, size: figure.size * scale,
            width: width, height: height,
            origin: CGPoint(
              x: (figure.origin.x - rect.minX) * scale,
              y: (figure.origin.y - rect.minY) * scale))
        }
        return [UInt8](repeating: 0, count: width * height)
      }
      if comparing {
        GlyphOverlay.draw(
          masks[0], masks[1], width: width, height: height, context: context, rect: rect,
          differentiateWithoutColor: differentiateWithoutColor, scale: zoom)
      } else {
        let ink = figures[0].installed ? masks[0] : masks[1]
        GlyphOverlay.draw(ink, ink, width: width, height: height, context: context, rect: rect)
      }
    }
  }

  private struct OverlayKey: Equatable {
    let comparison: Comparison
    let size: CGSize
  }
}
