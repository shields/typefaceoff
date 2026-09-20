import AppKit
import CoreText
import SwiftUI
import TypefaceCore

struct GlyphComparisonView: View {
  let comparison: Comparison
  let focusRequest: UUID
  let select: (String) -> Void
  let navigate: (Int) -> Void
  let showText: () -> Void
  let focusChanged: (Bool) -> Void
  @State private var input = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Button("Previous character", systemImage: "chevron.left") { navigate(-1) }.labelStyle(
          .iconOnly
        )
        .help("Inspect the previous character (Left Arrow when the glyph view has focus)")
        TextField("Character", text: $input).frame(width: 40).multilineTextAlignment(.center)
          .onSubmit {
            select(input)
            input = comparison.selectedGlyph
          }
        Button("Next character", systemImage: "chevron.right") { navigate(1) }.labelStyle(.iconOnly)
          .help("Inspect the next character (Right Arrow when the glyph view has focus)")
        Text(verbatim: unicodeDescription(comparison.selectedGlyph)).font(.system(size: 11))
          .foregroundStyle(.secondary).lineLimit(2)
          .help(unicodeDescription(comparison.selectedGlyph))
      }.frame(height: 32).padding(16)
      GlyphCanvas(
        comparison: comparison, focusRequest: focusRequest, navigate: navigate, showText: showText,
        focusChanged: focusChanged
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      HStack(alignment: .top, spacing: 0) {
        metrics(comparison.a)
        if let b = comparison.b {
          Color.clear.frame(maxWidth: .infinity).frame(height: 85)
          metrics(b)
        }
      }.frame(height: 85, alignment: .top).padding(.bottom, 16)
    }
    .background(.white).foregroundStyle(Color(white: 0.18)).environment(\.colorScheme, .light)
    .onChange(of: comparison.selectedGlyph, initial: true) { _, value in input = value }
  }

  private func metrics(_ config: FontConfiguration) -> some View {
    let metric = FontRenderer.nativeMetrics(comparison.selectedGlyph, config: config)
    return VStack(spacing: 7) {
      if FontRenderer.supports(comparison.selectedGlyph, config: config) {
        metricRow("Advance", value: metric.advance, em: config.face.unitsPerEm)
        metricRow("LSB", value: metric.leftBearing, em: config.face.unitsPerEm)
        metricRow("RSB", value: metric.rightBearing, em: config.face.unitsPerEm)
      } else {
        Text(FontRenderer.isAvailable(config) ? "Character unavailable" : "Font unavailable")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.horizontal, 12).frame(maxWidth: .infinity)
  }

  private func metricRow(_ title: String, value: Double, em: Int) -> some View {
    HStack(spacing: 4) {
      Text(verbatim: title)
      Spacer(minLength: 2)
      Text(verbatim: "\(number(value, digits: 0)) u").frame(minWidth: 45, alignment: .trailing)
      Text(verbatim: "\(number(value / Double(em), digits: 3)) em").frame(
        minWidth: 65, alignment: .trailing)
    }.font(.system(size: 11)).monospacedDigit().foregroundStyle(Color(white: 0.35))
  }
}

struct GlyphCanvas: NSViewRepresentable {
  let comparison: Comparison
  let focusRequest: UUID
  let navigate: (Int) -> Void
  let showText: () -> Void
  let focusChanged: (Bool) -> Void
  func makeNSView(context: Context) -> GlyphDrawingView { GlyphDrawingView() }
  func updateNSView(_ view: GlyphDrawingView, context: Context) {
    view.navigate = navigate
    view.showText = showText
    view.focusChanged = focusChanged
    view.update(comparison)
    view.requestFocus(focusRequest)
  }
}

final class GlyphDrawingView: NSView {
  var navigate: (Int) -> Void = { _ in }
  var showText: () -> Void = {}
  var focusChanged: (Bool) -> Void = { _ in }
  private var focusRequest: UUID?
  private var comparison = Comparison()
  private var envelope = GlyphMeasurementPlaceholder.defaultBounds
  private var envelopeKey: EnvelopeKey?
  private let red = NSColor(calibratedRed: 0.76, green: 0.32, blue: 0.31, alpha: 1)
  private let blue = NSColor(calibratedRed: 0.25, green: 0.48, blue: 0.68, alpha: 1)

  override var acceptsFirstResponder: Bool { true }

  var hasKeyboardFocus: Bool {
    window?.isKeyWindow == true && window?.firstResponder === self
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    updateFocusAppearance()
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    let accepted = super.resignFirstResponder()
    updateFocusAppearance()
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
          self, selector: #selector(updateFocusAppearance), name: name, object: window)
      }
    }
    if focusRequest != nil { window?.makeFirstResponder(self) }
    updateFocusAppearance()
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func updateFocusAppearance() {
    // First-responder callbacks run before the window finishes changing responders.
    // Defer the SwiftUI state update until both AppKit and view updates finish.
    Task { @MainActor [weak self] in
      guard let self else { return }
      needsDisplay = true
      focusChanged(hasKeyboardFocus)
    }
  }

  override func mouseDown(with event: NSEvent) {
    showText()
  }

  override func accessibilityPerformPress() -> Bool {
    showText()
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
    comparison = value
    let key = EnvelopeKey(a: value.a, b: value.b, text: value.text)
    if envelopeKey != key {
      let measured = FontRenderer.envelope(a: value.a, b: value.b, sample: value.text)
      envelope = measured.bounds.union(CGRect(x: 0, y: 0, width: measured.advance, height: 1))
      envelopeKey = key
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(
      value.b == nil
        ? "\(unicodeDescription(value.selectedGlyph)). Font A."
        : "\(unicodeDescription(value.selectedGlyph)). Font A in red, font B in blue, shared ink in black."
    )
    setAccessibilityHelp(
      "Click to return to text. Use the Left Arrow and Right Arrow keys to inspect ranked characters."
    )
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 0, bounds.height > 0
    else { return }
    NSColor.white.setFill()
    bounds.fill()
    if hasKeyboardFocus {
      NSColor.keyboardFocusIndicatorColor.setStroke()
      let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 4, yRadius: 4)
      ring.lineWidth = 2
      ring.stroke()
    }
    let count = comparison.b == nil ? 1 : 3
    let width = bounds.width / Double(count)
    let baseline = max(38, (bounds.height - 48) * 0.25)
    let scale = max(
      0.01,
      min(
        (width - 28) / max(1, envelope.width),
        (bounds.height - baseline - 60) / max(1, envelope.maxY),
        (baseline - 20) / max(1, -envelope.minY), 3.4))
    let configs = [comparison.a, comparison.b].compactMap { $0 }
    let sizes = configs.map { 100 * $0.size / comparison.a.size * scale }
    let xHeights = zip(configs, sizes).map { FontRenderer.xHeight(config: $0, size: $1) }
    let metrics = zip(configs, sizes).map {
      FontRenderer.measure(comparison.selectedGlyph, config: $0, size: $1)
    }
    let advances = zip(metrics, zip(configs, sizes)).map { $0.advance + $1.0.tracking * $1.1 }
    let supported = configs.map { FontRenderer.supports(comparison.selectedGlyph, config: $0) }
    let spacingOnly = comparison.spacing && !comparison.shape
    for column in 0..<count {
      let overlay = count == 3 && column == 1
      let indexes = overlay ? [0, 1] : [column == 2 ? 1 : 0]
      let start = Double(column) * width
      if column > 0 {
        stroke(
          context, from: CGPoint(x: start, y: 4), to: CGPoint(x: start, y: bounds.height - 5),
          color: .init(gray: 0.86, alpha: 1))
      }
      let config = configs[indexes[0]]
      let available = FontRenderer.isAvailable(config)
      let title = overlay ? "Overlay" : available ? config.face.family : "Font unavailable"
      label(title, x: start, y: bounds.height - 23, width: width, size: 12, centered: true)
      if !overlay {
        label(
          available ? "\(config.face.unitsPerEm) units/em" : config.postScriptName, x: start,
          y: bounds.height - 40,
          width: width, size: 10, centered: true)
      }
      stroke(
        context, from: CGPoint(x: start + 8, y: baseline),
        to: CGPoint(x: start + width - 8, y: baseline), color: .init(gray: 0.75, alpha: 1))
      label("baseline", x: start + 10, y: baseline - 16, width: width - 20, size: 9)
      let maxInk =
        overlay
        ? max(metrics[0].bounds.width, metrics[1].bounds.width) : metrics[indexes[0]].bounds.width
      let maxAdvance = overlay ? max(advances[0], advances[1]) : advances[indexes[0]]
      var masks: [[UInt8]] = []
      let pixelScale = window?.backingScaleFactor ?? 2
      let bitmapWidth = max(1, Int(ceil(width * pixelScale)))
      let bitmapHeight = max(1, Int(ceil(bounds.height * pixelScale)))
      for index in indexes {
        let metric = metrics[index]
        let originX =
          spacingOnly ? (width - maxAdvance) / 2 : (width - maxInk) / 2 - metric.bounds.minX
        let color = index == 0 ? red : blue
        if let xHeight = xHeights[index] {
          stroke(
            context, from: CGPoint(x: start + 8, y: baseline + xHeight),
            to: CGPoint(x: start + width - 8, y: baseline + xHeight),
            color: color.withAlphaComponent(0.35).cgColor, dashed: true)
          if index == indexes.first(where: { xHeights[$0] != nil }) {
            label("x-height", x: start + 10, y: baseline + xHeight + 4, width: width - 20, size: 9)
          }
        } else if !overlay {
          label(
            "x-height unavailable", x: start, y: bounds.height - 55, width: width, size: 9,
            centered: true)
        }
        for offset in [0, advances[index]] {
          stroke(
            context, from: CGPoint(x: start + originX + offset, y: 10),
            to: CGPoint(x: start + originX + offset, y: bounds.height - 48),
            color: color.withAlphaComponent(0.5).cgColor, dashed: true)
        }
        if supported[index] {
          if overlay {
            masks.append(
              FontRenderer.mask(
                comparison.selectedGlyph, config: configs[index], size: sizes[index] * pixelScale,
                width: bitmapWidth, height: bitmapHeight,
                origin: CGPoint(x: originX * pixelScale, y: baseline * pixelScale)))
          } else {
            context.saveGState()
            context.clip(
              to: CGRect(x: start + 1, y: 0, width: width - 2, height: bounds.height - 45))
            context.textPosition = CGPoint(x: start + originX, y: baseline)
            CTLineDraw(
              FontRenderer.line(
                comparison.selectedGlyph, config: configs[index], size: sizes[index]), context)
            context.restoreGState()
          }
        }
      }
      if overlay, masks.count == 2 {
        drawOverlay(
          masks[0], masks[1], width: bitmapWidth, height: bitmapHeight, context: context,
          rect: CGRect(x: start, y: 0, width: width, height: bounds.height))
      } else if indexes.contains(where: { !supported[$0] }) {
        label(
          "Character unavailable", x: start + 8, y: baseline + 25, width: width - 16, size: 12,
          centered: true)
      }
    }
  }

  private func drawOverlay(
    _ a: [UInt8], _ b: [UInt8], width: Int, height: Int, context: CGContext, rect: CGRect
  ) {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in a.indices {
      let left = Double(a[index]) / 255
      let right = Double(b[index]) / 255
      let shared = min(left, right)
      let alpha = max(left, right)
      for (channel, values) in [(0, (0.76, 0.25)), (1, (0.32, 0.48)), (2, (0.31, 0.68))] {
        pixels[index * 4 + channel] = UInt8(
          min(
            255,
            max(0, ((left - shared) * values.0 + (right - shared) * values.1 + shared * 0.14) * 255)
          ))
      }
      pixels[index * 4 + 3] = UInt8(alpha * 255)
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { return }
    context.draw(image, in: rect)
  }

  private func stroke(
    _ context: CGContext, from: CGPoint, to: CGPoint, color: CGColor, dashed: Bool = false
  ) {
    context.saveGState()
    context.setStrokeColor(color)
    context.setLineWidth(0.75)
    context.setLineDash(phase: 0, lengths: dashed ? [3, 4] : [])
    context.move(to: from)
    context.addLine(to: to)
    context.strokePath()
    context.restoreGState()
  }

  private func label(
    _ text: String, x: Double, y: Double, width: Double, size: Double, centered: Bool = false
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = centered ? .center : .left
    (text as NSString).draw(
      in: CGRect(x: x, y: y, width: width, height: 18),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.darkGray,
        .paragraphStyle: paragraph,
      ])
  }

  private struct EnvelopeKey: Equatable {
    let a: FontConfiguration
    let b: FontConfiguration?
    let text: String
  }
  private enum GlyphMeasurementPlaceholder {
    static let defaultBounds = CGRect(x: 0, y: -25, width: 100, height: 125)
  }
}
