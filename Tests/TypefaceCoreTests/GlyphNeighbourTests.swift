// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
