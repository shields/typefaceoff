import Testing

@testable import TypefaceOff

struct GlyphOverlayTests {
  @Test func colorsAndTransparencyMatchEveryPairOfCoverageValues() {
    let a = (0..<65_536).map { UInt8($0 / 256) }
    let b = (0..<65_536).map { UInt8($0 % 256) }
    let pixels = GlyphOverlay.pixels(a, b)
    let colors: [(Double, Double, Double)] = [
      (180.0 / 255, 40.0 / 255, 27.0 / 255),
      (59.0 / 255, 107.0 / 255, 28.0 / 255),
      (67.0 / 255, 157.0 / 255, 31.0 / 255),
    ]
    for index in a.indices {
      let left = Double(a[index])
      let right = Double(b[index])
      let shared = min(left, right)
      for channel in 0..<3 {
        let (red, blue, ink) = colors[channel]
        let expected = Int((left - shared) * red + (right - shared) * blue + shared * ink)
        // Single-precision SIMD may round to the adjacent 8-bit intensity.
        #expect(abs(Int(pixels[index * 4 + channel]) - expected) <= 1)
      }
      #expect(pixels[index * 4 + 3] == max(a[index], b[index]))
    }
  }

  @Test func solidInkUsesTheComparisonColorsAndSharedBlack() {
    #expect(
      GlyphOverlay.pixels([255, 0, 255, 0], [0, 255, 255, 0]) == [
        180, 59, 67, 255,
        40, 107, 157, 255,
        27, 28, 31, 255,
        0, 0, 0, 0,
      ])
  }
}
