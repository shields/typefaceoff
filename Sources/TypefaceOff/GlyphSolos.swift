import AppKit
import CoreText
import SwiftUI
import TypefaceCore

struct GlyphSolos: NSViewRepresentable {
  let comparison: Comparison
  let layout: GlyphLayout

  func makeNSView(context: Context) -> GlyphSoloView { GlyphSoloView() }
  func updateNSView(_ view: GlyphSoloView, context: Context) {
    view.comparison = comparison
    view.layout = layout
    view.setAccessibilityElement(comparison.b != nil)
    view.setAccessibilityRole(.image)
    view.setAccessibilityIdentifier("Individual glyphs")
    view.setAccessibilityLabel(
      [Side.a, .b].compactMap { side in
        comparison[side].map { config in
          let status =
            !FontRenderer.isAvailable(config)
            ? "Not installed"
            : FontRenderer.supports(comparison.selectedGlyph, config: config)
              ? unicodeDescription(comparison.selectedGlyph) : "Character unavailable"
          return "\(side.fontName): \(status)"
        }
      }.joined(separator: ". "))
    view.needsDisplay = true
  }
}

final class GlyphSoloView: NSView {
  var comparison = Comparison()
  var layout: GlyphLayout?

  override func draw(_ dirtyRect: NSRect) {
    guard let layout, let context = NSGraphicsContext.current?.cgContext else { return }
    let baseline = bounds.height - layout.baseline
    if comparison.b != nil {
      for (side, x) in [(Side.a, layout.columnA), (.b, layout.columnB)] {
        let config = comparison[side]!
        let figure = GlyphFigure(
          config: config, glyph: comparison.selectedGlyph,
          size: layout.soloSize * config.size / comparison.a.size, x: x, baseline: baseline,
          alignInk: false)
        if let line = figure.line {
          for origin in [x, x + figure.advance] {
            GlyphRendering.stroke(
              context, from: CGPoint(x: origin, y: baseline - 56),
              to: CGPoint(x: origin, y: baseline + 208 * layout.soloSize / 240))
          }
          if let xHeight = figure.xHeight {
            GlyphRendering.stroke(
              context, from: CGPoint(x: x - 12, y: baseline + xHeight),
              to: CGPoint(x: x + figure.advance + 12, y: baseline + xHeight))
          }
          context.saveGState()
          context.textMatrix = .identity
          context.textPosition = figure.origin
          CTLineDraw(line, context)
          context.restoreGState()
        } else if figure.installed {
          GlyphRendering.label(
            "Character unavailable", at: CGPoint(x: x, y: baseline + 10), width: layout.columnWidth)
        } else {
          GlyphRendering.label(
            "This font is not installed.", at: CGPoint(x: x, y: baseline + 26),
            width: layout.columnWidth)
          GlyphRendering.label(
            "Choose an installed font above.", at: CGPoint(x: x, y: baseline + 10),
            width: layout.columnWidth)
        }
      }
    }
    GlyphRendering.stroke(
      context, from: CGPoint(x: 0, y: baseline), to: CGPoint(x: bounds.width, y: baseline),
      ink: true)
  }
}
