import AppKit
import SwiftUI
import TypefaceCore

struct GlyphDifferencePreview: NSViewRepresentable {
  let glyph: String
  let a: FontConfiguration
  let b: FontConfiguration
  let spacingOnly: Bool
  var index = false
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  func makeNSView(context: Context) -> GlyphDifferenceDrawingView { GlyphDifferenceDrawingView() }

  func updateNSView(_ view: GlyphDifferenceDrawingView, context: Context) {
    view.preview = self
    view.differentiateWithoutColor = differentiateWithoutColor
    view.needsDisplay = true
  }
}

final class GlyphDifferenceDrawingView: NSView {
  var preview: GlyphDifferencePreview?
  var differentiateWithoutColor = false

  override func draw(_ dirtyRect: NSRect) {
    guard let preview, let context = NSGraphicsContext.current?.cgContext,
      bounds.width > 0, bounds.height > 0
    else { return }
    (preview.index ? NSColor(WorkbenchStyle.paper) : NSColor.white).setFill()
    bounds.fill()
    let configs = [preview.a, preview.b]
    guard configs.allSatisfy({ FontRenderer.supports(preview.glyph, config: $0) }) else {
      ("⚠︎ Unavailable" as NSString).draw(
        at: CGPoint(x: 2, y: bounds.midY - 5),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(WorkbenchStyle.ink),
        ])
      return
    }
    let size = preview.index ? 26.0 : 30
    let sizes = [size, size * preview.b.size / preview.a.size]
    let metrics = zip(configs, sizes).map {
      FontRenderer.measure(preview.glyph, config: $0, size: $1)
    }
    // Shape overlays align the ink; spacing overlays retain the fonts' side bearings.
    let offsets = metrics.map { preview.spacingOnly ? 0 : -$0.bounds.minX }
    var envelope = metrics.indices.reduce(CGRect.null) {
      $0.union(metrics[$1].bounds.offsetBy(dx: offsets[$1], dy: 0))
    }
    if preview.spacingOnly {
      for index in configs.indices {
        let advance = metrics[index].advance + configs[index].tracking * sizes[index]
        envelope = envelope.union(CGRect(x: min(0, advance), y: 0, width: abs(advance), height: 1))
      }
    }
    let scale =
      preview.index
      ? 1
      : max(
        0.01,
        min(
          1, (bounds.width - 8) / max(1, envelope.width),
          (bounds.height - 6) / max(1, envelope.height)))
    let origin =
      preview.index
      ? CGPoint(x: -envelope.minX, y: 14)
      : CGPoint(
        x: (bounds.width - envelope.width * scale) / 2 - envelope.minX * scale,
        y: (bounds.height - envelope.height * scale) / 2 - envelope.minY * scale)
    let pixelScale = window?.backingScaleFactor ?? 2
    let width = max(1, Int(ceil(bounds.width * pixelScale)))
    let height = max(1, Int(ceil(bounds.height * pixelScale)))
    let masks = configs.indices.map { index in
      FontRenderer.mask(
        preview.glyph, config: configs[index], size: sizes[index] * scale * pixelScale,
        width: width, height: height,
        origin: CGPoint(
          x: (origin.x + offsets[index] * scale) * pixelScale, y: origin.y * pixelScale))
    }
    GlyphOverlay.draw(
      masks[0], masks[1], width: width, height: height, context: context, rect: bounds,
      differentiateWithoutColor: differentiateWithoutColor)
  }
}
