import AppKit
import CoreText
import TypefaceCore

enum GlyphRendering {
  static func layout(_ comparison: Comparison, width: Double, height: Double) -> GlyphLayout {
    var ascent = 0.75
    var descent = 0.2
    for config in [comparison.a, comparison.b].compactMap({ $0 })
    where FontRenderer.isAvailable(config) {
      let font = FontRenderer.font(config, size: config.size / comparison.a.size)
      ascent = max(ascent, CTFontGetCapHeight(font))
      descent = max(descent, CTFontGetDescent(font))
    }
    return GlyphLayout(width: width, height: height, ascent: ascent, descent: descent)
  }

  static func stroke(_ context: CGContext, from: CGPoint, to: CGPoint, ink: Bool = false) {
    context.saveGState()
    context.setStrokeColor(NSColor(ink ? WorkbenchStyle.ink : WorkbenchStyle.hairline).cgColor)
    context.setLineWidth(
      1 / max(1, abs(context.convertToDeviceSpace(CGSize(width: 1, height: 1)).width)))
    func aligned(_ point: CGPoint) -> CGPoint {
      let pixel = context.convertToDeviceSpace(point)
      return context.convertToUserSpace(CGPoint(x: floor(pixel.x) + 0.5, y: floor(pixel.y) + 0.5))
    }
    context.move(to: aligned(from))
    context.addLine(to: aligned(to))
    context.strokePath()
    context.restoreGState()
  }

  static func label(
    _ text: String, at point: CGPoint, width: Double,
    color: NSColor = NSColor(WorkbenchStyle.secondaryInk),
    bold: Bool = false
  ) {
    (text as NSString).draw(
      in: CGRect(x: point.x, y: point.y, width: width, height: 16),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: bold ? .bold : .regular),
        .foregroundColor: color,
      ])
  }
}

struct GlyphFigure {
  let config: FontConfiguration?
  let installed: Bool
  let size: Double
  let line: CTLine?
  let origin: CGPoint
  let advance: Double
  let xHeight: Double?

  init(
    config: FontConfiguration?, glyph: String, size: Double, x: Double, baseline: Double,
    alignInk: Bool
  ) {
    self.config = config
    self.size = size
    installed = config.map { FontRenderer.isAvailable($0) } == true
    if let config, installed && FontRenderer.supports(glyph, config: config) {
      var attributes = FontRenderer.attributes(config, size: size, tracking: false)
      attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] =
        NSColor(WorkbenchStyle.ink).cgColor
      line = CTLineCreateWithAttributedString(
        NSAttributedString(string: glyph, attributes: attributes))
      let metric = FontRenderer.measure(glyph, config: config, size: size)
      origin = CGPoint(x: x - (alignInk ? metric.bounds.minX : 0), y: baseline)
      advance = metric.advance + config.tracking * size
      xHeight = FontRenderer.xHeight(config: config, size: size)
    } else {
      line = nil
      origin = CGPoint(x: x, y: baseline)
      advance = 0
      xHeight = nil
    }
  }
}
