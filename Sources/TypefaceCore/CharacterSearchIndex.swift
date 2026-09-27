import Foundation

/// Search over the running system's Unicode character names, following raycast-charp.
struct CharacterSearchIndex: Sendable {
  struct Entry: Sendable {
    let scalar: Unicode.Scalar
    let name: String?
    let alias: String?
  }

  static let shared = CharacterSearchIndex(entries: platformEntries())
  static let maximumResults = 200
  static let fuzzyMinimumLength = 4

  /// Rows in popularity order, so a row's index is its final tie-break.
  let scalars: [Unicode.Scalar]
  /// Sorted bytewise, so each prefix's words are contiguous.
  let vocabulary: [[UInt8]]
  let postingStarts: [Int]
  let postings: [Int32]
  let nameWordStarts: [Int]
  let nameWords: [Int32]
  /// Keyed by scalars because string keys would merge canonically equivalent characters.
  let exactRows: [[Unicode.Scalar]: [Int32]]

  static func platformEntries() -> [Entry] {
    var entries: [Entry] = []
    for value in UInt32(0)...0x10FFFF {
      guard let scalar = Unicode.Scalar(value), let name = scalar.properties.name,
        !isPlaceholder(name, of: scalar)
      else { continue }
      entries.append(Entry(scalar: scalar, name: name, alias: scalar.properties.nameAlias))
    }
    // Common ideographs stay reachable by their code points.
    for scalar in CharacterFrequency.table.keys
    where scalar.properties.name.map({ isPlaceholder($0, of: scalar) }) != false {
      entries.append(Entry(scalar: scalar, name: nil, alias: nil))
    }
    return entries
  }

  /// Generic names such as "CJK UNIFIED IDEOGRAPH-4E00", recognized by their suffix rather
  /// than by code point ranges, which drift as Unicode adds blocks.
  static func isPlaceholder(_ name: String, of scalar: Unicode.Scalar) -> Bool {
    let hex = String(scalar.value, radix: 16, uppercase: true)
    return name.hasSuffix("-" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex)
  }

  init(entries: [Entry]) {
    var shares: [Double] = []
    for entry in entries { shares.append(CharacterFrequency.table[entry.scalar] ?? 0) }
    let order = entries.indices.sorted { a, b in
      shares[a] != shares[b]
        ? shares[a] > shares[b] : entries[a].scalar.value < entries[b].scalar.value
    }
    precondition(order.count < Int(Int32.max))
    var scalars: [Unicode.Scalar] = []
    var nameTokens: [[[UInt8]]] = []
    var aliasTokens: [[[UInt8]]] = []
    var distinct = Set<[UInt8]>()
    var exactRows: [[Unicode.Scalar]: [Int32]] = [:]
    func tokens(_ text: String?) -> [[UInt8]] { Self.words(text ?? "").map { Array($0.utf8) } }
    for index in order {
      let entry = entries[index]
      let names = tokens(entry.name)
      let aliases = tokens(entry.alias)
      distinct.formUnion(names)
      distinct.formUnion(aliases)
      exactRows[Array(String(entry.scalar).lowercased().unicodeScalars), default: []].append(
        Int32(scalars.count))
      scalars.append(entry.scalar)
      nameTokens.append(names)
      aliasTokens.append(aliases)
    }
    let vocabulary = distinct.sorted { $0.lexicographicallyPrecedes($1) }
    var ids: [[UInt8]: Int32] = [:]
    for (id, word) in vocabulary.enumerated() { ids[word] = Int32(id) }
    var postingStarts = [Int](repeating: 0, count: vocabulary.count + 1)
    var nameWordStarts = [0]
    var nameWords: [Int32] = []
    for row in scalars.indices {
      for word in nameTokens[row] { postingStarts[Int(ids[word]!) + 1] += 1 }
      for word in aliasTokens[row] { postingStarts[Int(ids[word]!) + 1] += 1 }
      for word in nameTokens[row] { nameWords.append(ids[word]!) }
      nameWordStarts.append(nameWords.count)
    }
    for id in vocabulary.indices { postingStarts[id + 1] += postingStarts[id] }
    var cursor = postingStarts
    var postings = [Int32](repeating: 0, count: postingStarts[vocabulary.count])
    func fill(_ word: [UInt8], row: Int) {
      let id = Int(ids[word]!)
      postings[cursor[id]] = Int32(row)
      cursor[id] += 1
    }
    for row in scalars.indices {
      for word in nameTokens[row] { fill(word, row: row) }
      for word in aliasTokens[row] { fill(word, row: row) }
    }
    self.scalars = scalars
    self.vocabulary = vocabulary
    self.postingStarts = postingStarts
    self.postings = postings
    self.nameWordStarts = nameWordStarts
    self.nameWords = nameWords
    self.exactRows = exactRows
  }

  /// raycast-charp's tokenizer, shared by queries and names so that they match symmetrically.
  static func words(_ text: String) -> [String] {
    var result: [String] = []
    for chunk in text.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "-" }) {
      guard let first = chunk.firstIndex(where: isWordCharacter),
        let last = chunk.lastIndex(where: isWordCharacter)
      else { continue }
      result.append(String(chunk[first...last]))
    }
    return result
  }

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber
  }

  /// A query of symbols alone, such as "→" or "-", matches as one character.
  static func terms(_ trimmed: String) -> [String] {
    let words = words(trimmed)
    return words.isEmpty ? [trimmed.lowercased()] : words
  }

  static func codePointGlyph(_ text: String) -> String? {
    var scalars = String.UnicodeScalarView()
    for token in text.split(whereSeparator: \.isWhitespace) {
      let token = token.lowercased()
      guard token.hasPrefix("u+") || token.hasPrefix("0x"), let pattern = hexPattern(token),
        let scalar = Unicode.Scalar(pattern.value)
      else { return nil }
      scalars.append(scalar)
    }
    let glyph = String(scalars)
    return glyph.count == 1 ? glyph : nil
  }

  static func hexPattern(_ term: String) -> (value: UInt32, digits: Int)? {
    let digits = term.hasPrefix("u+") || term.hasPrefix("0x") ? term.dropFirst(2) : Substring(term)
    guard (1...6).contains(digits.utf8.count),
      digits.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) })
    else { return nil }
    return (UInt32(digits, radix: 16)!, digits.utf8.count)
  }

  /// Whether the pattern's digits appear in the code point written as "%04X".
  static func hexContains(_ value: UInt32, _ pattern: (value: UInt32, digits: Int)) -> Bool {
    let width = max(4, (32 - value.leadingZeroBitCount + 3) / 4)
    guard pattern.digits <= width else { return false }
    let mask: UInt32 = (1 << (4 * pattern.digits)) - 1
    for shift in 0...(width - pattern.digits)
    where (value >> (4 * shift)) & mask == pattern.value {
      return true
    }
    return false
  }

  /// The pinned glyph leads regardless of score: the character typed as is, then one
  /// spelled as code points, so every scalar and cluster is reachable.
  func search(_ query: String, missingFonts: (Unicode.Scalar) -> Int) throws -> [String] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let pin = query.count == 1 ? query : trimmed.count == 1 ? trimmed : Self.codePointGlyph(trimmed)
    var results = pin.map { [$0] } ?? []
    guard !trimmed.isEmpty else { return results }
    let terms = Self.terms(trimmed)
    var matches = try self.matches(terms, fuzzy: false, missingFonts: missingFonts)
    // Only a query that otherwise finds nothing pays for edit distances, which count scalars.
    let longEnoughToFuzzyMatch = terms.contains {
      $0.unicodeScalars.count >= Self.fuzzyMinimumLength
    }
    if matches.isEmpty, longEnoughToFuzzyMatch {
      matches = try self.matches(terms, fuzzy: true, missingFonts: missingFonts)
    }
    matches.sort { $0.precedes($1) }
    let pinned = pin.map { Array($0.unicodeScalars) }
    for match in matches {
      guard results.count < Self.maximumResults else { break }
      let scalar = scalars[Int(match.row)]
      if pinned != [scalar] { results.append(String(scalar)) }
    }
    return results
  }

  struct Match {
    let row: Int32
    let bucket: Int
    let charHit: Bool
    let covered: Int
    let words: Int
    let score: UInt8
    let missing: Int

    func precedes(_ other: Match) -> Bool {
      if bucket != other.bucket { return bucket < other.bucket }
      if charHit != other.charHit { return charHit }
      let coverage = covered * other.words
      let otherCoverage = other.covered * words
      if coverage != otherCoverage { return coverage > otherCoverage }
      if score != other.score { return score > other.score }
      if missing != other.missing { return missing < other.missing }
      return row < other.row
    }
  }

  func matches(_ terms: [String], fuzzy: Bool, missingFonts: (Unicode.Scalar) -> Int) throws
    -> [Match]
  {
    let (scores, charHits, prefixes) = try scores(terms, fuzzy: fuzzy)
    var result: [Match] = []
    for row in scalars.indices where scores[row] > 0 {
      let names = nameWords[nameWordStarts[row]..<nameWordStarts[row + 1]]
      // Fuzzy matches don't count, so a typo can't make a longer name look complete.
      let covered = names.count { word in prefixes.contains { $0.contains(Int(word)) } }
      result.append(
        Match(
          row: Int32(row), bucket: Self.bucket(scores[row]), charHit: charHits[row],
          covered: covered, words: max(1, names.count), score: scores[row],
          missing: missingFonts(scalars[row])))
    }
    return result
  }

  /// Merging the exact-word and prefix tiers lets a canonical prefix match ("left" in
  /// "LEFTWARDS") compete with exact words on coverage and popularity.
  static func bucket(_ score: UInt8) -> Int {
    switch score {
    case 100: 0
    case 60...80: 1
    case 20: 2
    default: 3
    }
  }

  /// Each row's weakest term score, so that every term must match.
  func scores(
    _ terms: [String], fuzzy: Bool
  ) throws -> (scores: [UInt8], charHits: [Bool], prefixes: [Range<Int>]) {
    var combined = [UInt8](repeating: terms.isEmpty ? 0 : 100, count: scalars.count)
    var charHits = [Bool](repeating: false, count: scalars.count)
    var prefixes: [Range<Int>] = []
    var scores = [UInt8](repeating: 0, count: scalars.count)
    for term in terms {
      try Task.checkCancellation()
      for index in scores.indices { scores[index] = 0 }
      for row in exactRows[Array(term.unicodeScalars)] ?? [] {
        scores[Int(row)] = 100
        charHits[Int(row)] = true
      }
      let bytes = Array(term.utf8)
      let prefix = prefixRange(bytes)
      prefixes.append(prefix)
      for word in prefix {
        raise(&scores, word, to: vocabulary[word].count == bytes.count ? 80 : 60)
      }
      for word in vocabulary.indices where Self.contains(vocabulary[word], bytes) {
        raise(&scores, word, to: 20)
      }
      if let pattern = Self.hexPattern(term) {
        for row in scalars.indices where Self.hexContains(scalars[row].value, pattern) {
          scores[row] = max(scores[row], 20)
          // A term spelling out the whole code point identifies the character, like typing it.
          if pattern.digits >= 4, scalars[row].value == pattern.value { charHits[row] = true }
        }
      }
      let values = term.unicodeScalars.map(\.value)
      if fuzzy, values.count >= Self.fuzzyMinimumLength {
        for word in vocabulary.indices where Self.fuzzyMatch(vocabulary[word], values) {
          raise(&scores, word, to: 10)
        }
      }
      for row in combined.indices { combined[row] = min(combined[row], scores[row]) }
    }
    return (combined, charHits, prefixes)
  }

  private func raise(_ scores: inout [UInt8], _ word: Int, to tier: UInt8) {
    for row in postings[postingStarts[word]..<postingStarts[word + 1]] {
      scores[Int(row)] = max(scores[Int(row)], tier)
    }
  }

  func prefixRange(_ term: [UInt8]) -> Range<Int> {
    let lower = partition(from: 0) { !$0.lexicographicallyPrecedes(term) }
    return lower..<partition(from: lower) { !$0.starts(with: term) }
  }

  private func partition(from start: Int, where predicate: ([UInt8]) -> Bool) -> Int {
    var low = start
    var high = vocabulary.count
    while low < high {
      let middle = (low + high) / 2
      if predicate(vocabulary[middle]) { high = middle } else { low = middle + 1 }
    }
    return low
  }

  static func contains(_ word: [UInt8], _ term: [UInt8]) -> Bool {
    guard term.count <= word.count else { return false }
    for start in 0...(word.count - term.count)
    where word[start..<start + term.count].elementsEqual(term) {
      return true
    }
    return false
  }

  /// A term within one edit of the word, or of a prefix about its length, so that a typo in
  /// a stem ("letf") still reaches a longer word ("LEFTWARDS").
  static func fuzzyMatch(_ word: [UInt8], _ term: [UInt32]) -> Bool {
    if withinOneEdit(term, ArraySlice(word)) { return true }
    for length in max(term.count - 1, 0)...term.count + 1 where length < word.count {
      if withinOneEdit(term, word.prefix(length)) { return true }
    }
    return false
  }

  /// Optimal string alignment distance of at most one, counting a transposition as one edit.
  static func withinOneEdit(_ term: [UInt32], _ word: ArraySlice<UInt8>) -> Bool {
    let word = word.map(UInt32.init)
    guard abs(term.count - word.count) <= 1 else { return false }
    var start = 0
    while start < min(term.count, word.count), term[start] == word[start] { start += 1 }
    func rest(_ a: Int, _ b: Int) -> Bool {
      term[min(a, term.count)...] == word[min(b, word.count)...]
    }
    return start == min(term.count, word.count) || rest(start + 1, start + 1)
      || rest(start + 1, start) || rest(start, start + 1)
      || (start + 1 < min(term.count, word.count) && term[start] == word[start + 1]
        && term[start + 1] == word[start] && rest(start + 2, start + 2))
  }
}
