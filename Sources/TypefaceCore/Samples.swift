import Foundation

public enum Sample: String, CaseIterable, Sendable {
  case reading, alphabet, numerals, custom

  public var title: String {
    switch self {
    case .reading: "Queen Alice"
    case .alphabet: "Alphabet"
    case .numerals: "Numerals & punctuation"
    case .custom: "Custom text"
    }
  }

  public var text: String {
    switch self {
    case .reading: String(QueenAlice.content.characters)
    case .alphabet:
      """
      Aa Bb Cc

      abcdefghijklmnopqrstuvwxyz
      ABCDEFGHIJKLMNOPQRSTUVWXYZ

      a g e s r t f j y
      G R Q M W K J
      Il1  O0  rn m  cl d  vv w

      ff fi fl ffi ffl
      office  affinity  shuffle  waffle

      Hamburgefontsiv
      The quick brown fox jumps over the lazy dog.
      """
    case .numerals:
      """
      0123456789

      $1,234.56   €789.00
      £42.50   ¥8,900

      10:24:08   09/18/2026
      1/2  3/4  5/8  7/16

      “Quotation” ‘apostrophe’
      (Parentheses) [brackets]
      & @ # % * + = / — …

      1,111.11
      8,888.88
      0,000.00
      """
    case .custom: ""
    }
  }

  /// Emphasis ranges in the plain text’s UTF-16 coordinates.
  public var italicRanges: [NSRange] {
    guard self == .reading else { return [] }
    var offset = 0
    return QueenAlice.content.runs.compactMap { run in
      let length = String(QueenAlice.content[run.range].characters).utf16.count
      defer { offset += length }
      return run.inlinePresentationIntent?.contains(.emphasized) == true
        ? NSRange(location: offset, length: length) : nil
    }
  }
}

public func unicodeDescription(_ glyph: String) -> String {
  glyph.unicodeScalars.map {
    "U+\(String(format: "%04X", $0.value)) \($0.properties.name ?? "UNNAMED CHARACTER")"
  }.joined(separator: " · ")
}
