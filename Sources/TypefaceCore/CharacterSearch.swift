import CoreText
import Foundation

public struct CharacterSearchResult: Identifiable, Hashable, Sendable {
  /// Scalar values rather than the string, which compares by canonical equivalence.
  public let id: [Unicode.Scalar]
  /// Whether each searched font, in order, draws the glyph without a fallback.
  public let supported: [Bool]

  /// Exactly one grapheme cluster, with the scalars that were searched or typed.
  public var glyph: String { String(String.UnicodeScalarView(id)) }

  public init(glyph: String, supported: [Bool]) {
    id = Array(glyph.unicodeScalars)
    self.supported = supported
  }
}

public enum CharacterSearch {
  /// Among equally good matches, characters that more of `fonts` have come first.
  @concurrent
  public static func results(for query: String, fonts: [FontConfiguration]) async throws
    -> [CharacterSearchResult]
  {
    let index = CharacterSearchIndex.shared
    let probeSize = 22.0
    // A missing font would lend the fallback font's coverage.
    let available = fonts.map {
      FontRenderer.isAvailable($0) ? FontRenderer.font($0, size: probeSize) : nil
    }
    let coverage = available.compactMap { $0.map(CTFontCopyCharacterSet) }
    let glyphs = try index.search(query) { missingFonts(for: $0, coverage: coverage) }
    var results: [CharacterSearchResult] = []
    for glyph in glyphs {
      try Task.checkCancellation()
      var supported: [Bool] = []
      for (config, font) in zip(fonts, available) {
        supported.append(
          font.map {
            FontRenderer.supports(
              FontRenderer.line(glyph, config: config, font: $0, size: probeSize, tracking: false),
              font: $0)
          } ?? false)
      }
      results.append(CharacterSearchResult(glyph: glyph, supported: supported))
    }
    return results
  }

  static func missingFonts(for scalar: Unicode.Scalar, coverage: [CFCharacterSet]) -> Int {
    // Default-ignorable code points shape to no glyphs, which `supports` accepts in any font.
    guard !scalar.properties.isDefaultIgnorableCodePoint else { return 0 }
    return coverage.count { !CFCharacterSetIsLongCharacterMember($0, scalar.value) }
  }
}
