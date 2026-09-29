import Testing

@testable import TypefaceCore

@Suite struct GlyphNeighbourTests {
  private func comparison(selecting glyph: String) -> Comparison {
    var comparison = Comparison(b: nil)
    comparison.selectedGlyph = glyph
    return comparison
  }

  @Test func navigationStepsThroughTheListAndWrapsAtBothEnds() {
    let glyphs = ["a", "b", "c"]
    #expect(comparison(selecting: "a").neighbour(in: glyphs, direction: 1) == "b")
    #expect(comparison(selecting: "b").neighbour(in: glyphs, direction: -1) == "a")
    #expect(comparison(selecting: "c").neighbour(in: glyphs, direction: 1) == "a")
    #expect(comparison(selecting: "a").neighbour(in: glyphs, direction: -1) == "c")
  }

  @Test func aSelectionOutsideTheListEntersItFromTheSideTheDirectionLeaves() {
    let glyphs = ["a", "b", "c"]
    #expect(comparison(selecting: "🦄").neighbour(in: glyphs, direction: 1) == "a")
    #expect(comparison(selecting: "🦄").neighbour(in: glyphs, direction: -1) == "c")
    #expect(comparison(selecting: "🦄").neighbour(in: ["a"], direction: 1) == "a")
    #expect(comparison(selecting: "🦄").neighbour(in: ["a"], direction: -1) == "a")
  }

  @Test func anEmptyListHasNoNeighbour() {
    #expect(comparison(selecting: "a").neighbour(in: [], direction: 1) == nil)
  }

  @Test func aCanonicallyEquivalentSpellingNavigatesFromItsPlaceInTheList() {
    let glyphs = ["a", "\u{E9}", "z"]
    #expect(comparison(selecting: "e\u{301}").neighbour(in: glyphs, direction: 1) == "z")
    #expect(comparison(selecting: "e\u{301}").neighbour(in: glyphs, direction: -1) == "a")
  }

  @Test func anExactScalarMatchWinsOverACanonicallyEquivalentEarlierEntry() {
    let glyphs = [";", "\u{37E}", "b"]
    #expect(comparison(selecting: "\u{37E}").neighbour(in: glyphs, direction: 1) == "b")
    #expect(comparison(selecting: "\u{37E}").neighbour(in: glyphs, direction: -1) == ";")
  }
}
