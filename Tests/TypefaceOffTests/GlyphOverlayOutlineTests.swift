import AppKit
import CoreText
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct GlyphOverlayOutlineTests {
  @Test(arguments: ["@", "g", "fi", "e\u{301}\u{323}", " "])
  func outlinesPreserveShapingAndPositions(glyph: String) throws {
    let config = FontConfiguration("HelveticaNeue")
    let origin = CGPoint(x: 23, y: 31)
    let line = FontRenderer.line(glyph, config: config, size: 128)
    let outline = try #require(GlyphOverlayOutline(a: line, b: line, origins: [origin, origin]))
    if glyph == " " {
      #expect(outline.a.isEmpty)
      #expect(outline.shared.isEmpty)
    } else {
      let bounds = FontRenderer.measure(glyph, config: config, size: 128).bounds
        .offsetBy(dx: origin.x, dy: origin.y)
      #expect(abs(outline.a.boundingBoxOfPath.minX - bounds.minX) < 0.01)
      #expect(abs(outline.a.boundingBoxOfPath.minY - bounds.minY) < 0.01)
      // Core Text's line bounds can be slightly wider than the tight Bézier contour bounds.
      #expect(abs(outline.a.boundingBoxOfPath.width - bounds.width) < 0.5)
      #expect(abs(outline.a.boundingBoxOfPath.height - bounds.height) < 0.01)
      #expect(abs(outline.shared.boundingBoxOfPath.width - bounds.width) < 0.5)
    }
  }

  @Test func sharedInkIsTheIntersectionIncludingCounters() throws {
    let outline = try #require(
      GlyphOverlayOutline(
        a: FontRenderer.line("@", config: .init("HelveticaNeue"), size: 128),
        b: FontRenderer.line("@", config: .init("ArialMT"), size: 128),
        origins: [CGPoint(x: 20, y: 35), CGPoint(x: 22, y: 35)]))
    var sharedPoints = 0
    var distinctPoints = 0
    for x in stride(from: 0.5, through: 170, by: 5) {
      for y in stride(from: 0.5, through: 170, by: 5) {
        let point = CGPoint(x: x, y: y)
        let a = outline.a.contains(point)
        let b = outline.b.contains(point)
        #expect(outline.shared.contains(point) == (a && b))
        if a && b { sharedPoints += 1 }
        if a != b { distinctPoints += 1 }
      }
    }
    #expect(sharedPoints > 0)
    #expect(distinctPoints > 0)
  }

  @Test func bitmapGlyphsUseTheRasterRenderer() throws {
    let config = FontConfiguration("AppleColorEmoji")
    try #require(FontRenderer.supports("🦄", config: config))
    let bitmap = FontRenderer.line("🦄", config: config, size: 128)
    let vector = FontRenderer.line("@", config: .init("HelveticaNeue"), size: 128)
    #expect(GlyphOverlayOutline(a: bitmap, b: vector, origins: [.zero, .zero]) == nil)
    #expect(GlyphOverlayOutline(a: vector, b: bitmap, origins: [.zero, .zero]) == nil)
    var comparison = Comparison(a: config, b: config)
    comparison.sample = .custom
    comparison.customText = "🦄"
    comparison.selectedGlyph = "🦄"
    let view = GlyphDrawingView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    view.update(comparison)
    let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: image)
    #expect(image.pixelsWide > 0)
  }
}
