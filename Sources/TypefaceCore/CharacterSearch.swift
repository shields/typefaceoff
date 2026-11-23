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
    // A missing font would lend the fallback font's coverage.
    let probes = fonts.map { FontRenderer.isAvailable($0) ? FontProbe($0) : nil }
    let available = probes.compactMap { $0 }
    let glyphs = try index.search(query, fontCount: available.count) { scalar in
      available.count { $0.lacks(scalar) }
    }
    var results: [CharacterSearchResult] = []
    for glyph in glyphs {
      try Task.checkCancellation()
      results.append(
        CharacterSearchResult(glyph: glyph, supported: probes.map { $0?.renders(glyph) ?? false }))
    }
    return results
  }
}

struct FontProbe {
  let config: FontConfiguration
  let font: CTFont
  let coverage: CFCharacterSet
  let configuredName: String

  init(_ config: FontConfiguration) {
    self.config = config
    font = FontRenderer.font(config, size: 22)
    coverage = CTFontCopyCharacterSet(font)
    configuredName = CTFontCopyPostScriptName(font) as String
  }

  func renders(_ glyph: String) -> Bool {
    FontRenderer.supports(
      FontRenderer.line(glyph, config: config, font: font, size: 22, tracking: false),
      configuredName: configuredName)
  }

  func lacks(_ scalar: Unicode.Scalar) -> Bool {
    let properties = scalar.properties
    // The cmap doesn't predict how invisible and format characters shape.
    guard !properties.isDefaultIgnorableCodePoint, properties.generalCategory != .format else {
      return !renders(String(scalar))
    }
    return !CFCharacterSetIsLongCharacterMember(coverage, scalar.value)
  }
}
