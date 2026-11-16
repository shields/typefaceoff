import Testing

@testable import TypefaceCore

@Suite struct GlyphLayoutTests {
  @Test func fullWidthMatchesTheDrawingAndInspectorPreservesTheOverlayScale() {
    let full = GlyphLayout(width: 1440, height: 665, ascent: 0.73, descent: 0.22)
    #expect(full.stageX == 752 && full.stageWidth == 688)
    #expect(full.baseline == 449 && full.overlaySize == 480 && full.soloSize == 240)
    #expect(full.columnA == 196 && full.columnB == 444 && full.columnWidth == 160)
    #expect(full.overlayOrigin == 88)
    let inspector = GlyphLayout(width: 1120, height: 665, ascent: 0.73, descent: 0.22)
    #expect(inspector.stageX == 592 && inspector.stageWidth == 528)
    #expect(inspector.overlaySize == 480 && inspector.soloSize == 160)
    #expect(inspector.overlayOrigin == 32)
    #expect(inspector.columnB + inspector.columnWidth <= inspector.stageX - 64)
    let minimum = GlyphLayout(width: 1076, height: 665, ascent: 0.73, descent: 0.22)
    #expect(minimum.overlaySize == 480)
  }

  @Test func narrowAndShortWindowsKeepTheMetricsAndScaleWithinTheStage() {
    let narrow = GlyphLayout(width: 960, height: 665, ascent: 0.73, descent: 0.22)
    #expect(abs(narrow.overlaySize - 480 * 448 / 506) < 0.001)
    #expect(narrow.columnA >= 140 && narrow.columnWidth >= 140)
    #expect(narrow.columnB + narrow.columnWidth == narrow.stageX - 64)
    let short = GlyphLayout(width: 1440, height: 418, ascent: 0.73, descent: 0.22)
    #expect(short.baseline == 202)
    #expect(short.overlaySize * 0.73 <= short.baseline - 30)
    let deep = GlyphLayout(width: 1440, height: 665, ascent: 0.73, descent: 0.5)
    #expect(deep.overlaySize == 224)
    let empty = GlyphLayout(width: 0, height: 0, ascent: 0, descent: 0)
    #expect(empty.baseline == 0 && empty.overlaySize == 0)
    #expect(empty.stageWidth == 448 && empty.columnWidth > 0)
  }

  @Test func guidesMergeOnlyWithinOnePhysicalPixelAndKeepBothLetters() {
    let merged = GlyphGuide.paired(a: 88, b: 88.5, pixelScale: 2)
    #expect(merged.count == 1 && merged[0].position == 88.25)
    #expect(merged[0].sides == [.a, .b])
    let separate = GlyphGuide.paired(a: 89, b: 88, pixelScale: 2)
    #expect(separate.map(\.position) == [88, 89])
    #expect(separate.map(\.sides) == [[.b], [.a]])
    #expect(GlyphGuide.paired(a: 88, b: nil, pixelScale: 2).first?.sides == [.a])
    #expect(GlyphGuide.paired(a: nil, b: 88, pixelScale: 2).first?.sides == [.b])
    #expect(GlyphGuide.paired(a: nil, b: nil, pixelScale: 2).isEmpty)
  }

  @Test func guideLettersKeepTheirMarginsAndNeverOverlapNearAnEdge() {
    for pair in [(2.0, 4.0), (420, 422), (100, 200)] {
      let guides = GlyphGuide.paired(a: pair.0, b: pair.1, pixelScale: 2)
      let positions = GlyphGuide.labelPositions(for: guides, width: 448)
      #expect(positions[0] >= 0 && positions[1] + 10 <= 424)
      #expect(positions[1] - positions[0] >= 14)
      if pair.1 > 400 { #expect(positions[1] + 10 <= pair.1 - 4) }
    }
    let merged = GlyphGuide.paired(a: 430, b: 430, pixelScale: 2)
    #expect(GlyphGuide.labelPositions(for: merged, width: 448) == [400])
    let single = GlyphGuide.paired(a: 100, b: nil, pixelScale: 2)
    #expect(GlyphGuide.labelPositions(for: single, width: 448) == [104])
    #expect(GlyphGuide.labelPositions(for: [], width: 448).isEmpty)
  }
}
