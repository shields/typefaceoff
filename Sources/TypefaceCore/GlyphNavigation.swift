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
