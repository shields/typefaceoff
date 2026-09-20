import Testing

@testable import TypefaceOff

struct GlyphOverlayTests {
  @Test func colorsAndTransparencyMatchEveryPairOfCoverageValues() {
    let a = (0..<65_536).map { UInt8($0 / 256) }
    let b = (0..<65_536).map { UInt8($0 % 256) }
    let pixels = GlyphOverlay.pixels(a, b)
    let colors = [(0.76, 0.25), (0.32, 0.48), (0.31, 0.68)]
    for index in a.indices {
      let left = Double(a[index])
      let right = Double(b[index])
      let shared = min(left, right)
      for channel in 0..<3 {
        let (red, blue) = colors[channel]
        let expected = Int((left - shared) * red + (right - shared) * blue + shared * 0.14)
        // Single-precision SIMD may round to the adjacent 8-bit intensity.
        #expect(abs(Int(pixels[index * 4 + channel]) - expected) <= 1)
      }
      #expect(pixels[index * 4 + 3] == max(a[index], b[index]))
    }
  }

  @Test func solidInkUsesTheComparisonColorsAndSharedBlack() {
    #expect(
      GlyphOverlay.pixels([255, 0, 255, 0], [0, 255, 255, 0]) == [
        193, 81, 79, 255,
        63, 122, 173, 255,
        35, 35, 35, 255,
        0, 0, 0, 0,
      ])
  }
}
