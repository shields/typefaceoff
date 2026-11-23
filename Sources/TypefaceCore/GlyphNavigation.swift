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

extension Comparison {
  /// The glyph one step from the selection in `glyphs`, wrapping at either end. A selection
  /// outside the list enters it from the side the direction moves away from, so Next reaches
  /// the first entry and Previous the last.
  public func neighbour(in glyphs: [String], direction: Int) -> String? {
    guard !glyphs.isEmpty else { return nil }
    // A canonically equivalent spelling still navigates from its place in the list.
    let index =
      glyphs.firstIndex { matches($0) } ?? glyphs.firstIndex(of: selectedGlyph)
      ?? (direction > 0 ? -1 : glyphs.count)
    return glyphs[(index + direction + glyphs.count) % glyphs.count]
  }
}
