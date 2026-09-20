import Foundation

public enum Sample: String, CaseIterable, Sendable {
  case reading, poetry, alphabet, numerals, custom

  public var title: String {
    switch self {
    case .reading: "Alice in Wonderland"
    case .poetry: "Jabberwocky"
    case .alphabet: "Alphabet"
    case .numerals: "Numerals & punctuation"
    case .custom: "Custom text"
    }
  }

  public var text: String {
    switch self {
    case .reading:
      """
      Down the Rabbit-Hole

      Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, “and what is the use of a book,” thought Alice “without pictures or conversations?”

      So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.

      Lewis Carroll · Alice’s Adventures in Wonderland
      """
    case .poetry:
      """
      Jabberwocky

      ’Twas brillig, and the slithy toves
          Did gyre and gimble in the wabe;
      All mimsy were the borogoves,
          And the mome raths outgrabe.

      “Beware the Jabberwock, my son!
          The jaws that bite, the claws that catch!
      Beware the Jubjub bird, and shun
          The frumious Bandersnatch!”

      He took his vorpal sword in hand:
          Long time the manxome foe he sought—
      So rested he by the Tumtum tree,
          And stood awhile in thought.

      Lewis Carroll · Through the Looking-Glass
      """
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
}

public func unicodeDescription(_ glyph: String) -> String {
  glyph.unicodeScalars.map {
    "U+\(String(format: "%04X", $0.value)) \($0.properties.name ?? "UNNAMED CHARACTER")"
  }.joined(separator: " · ")
}
