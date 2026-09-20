import CoreGraphics
import CoreText
import Foundation

/// Build the shared outline once; zooming and panning then use native vector drawing.
struct GlyphOverlayOutline {
  let a: CGPath
  let b: CGPath
  let shared: CGPath

  init?(a: CTLine, b: CTLine, origins: [CGPoint]) {
    guard let left = Self.path(a, origin: origins[0]),
      let right = Self.path(b, origin: origins[1])
    else { return nil }
    self.a = left
    self.b = right
    shared = left.intersection(right)
  }

  func draw(in context: CGContext, red: CGColor, blue: CGColor) {
    context.saveGState()
    for (path, color) in [(a, red), (b, blue), (shared, CGColor(gray: 0.14, alpha: 1))] {
      context.setFillColor(color)
      context.addPath(path)
      context.fillPath()
    }
    context.restoreGState()
  }

  private static func path(_ line: CTLine, origin: CGPoint) -> CGPath? {
    let result = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
      let attributes = CTRunGetAttributes(run) as NSDictionary
      let font = attributes[kCTFontAttributeName] as! CTFont
      let count = CTRunGetGlyphCount(run)
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      CTRunGetGlyphs(run, CFRange(), &glyphs)
      CTRunGetPositions(run, CFRange(), &positions)
      for index in glyphs.indices {
        guard let outline = CTFontCreatePathForGlyph(font, glyphs[index], nil) else {
          // Spaces have no ink. Bitmap/color glyphs need the raster compositor.
          var glyph = glyphs[index]
          let ink = CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, nil, 1)
          if !ink.isEmpty { return nil }
          continue
        }
        var transform = CTRunGetTextMatrix(run)
        transform.tx += origin.x + positions[index].x
        transform.ty += origin.y + positions[index].y
        result.addPath(outline, transform: transform)
      }
    }
    return result
  }
}
