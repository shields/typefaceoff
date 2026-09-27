import CoreText
import Foundation
import Testing

@testable import TypefaceCore

/// Name-dependent expectations use characters that every supported macOS names identically.
@Suite struct CharacterSearchTests {
  typealias Entry = CharacterSearchIndex.Entry
  let index = CharacterSearchIndex.shared
  let fonts = [FontConfiguration("HelveticaNeue"), FontConfiguration("ArialMT")]

  func ids(_ query: String, fonts: [FontConfiguration] = []) async throws -> [[Unicode.Scalar]] {
    try await CharacterSearch.results(for: query, fonts: fonts).map(\.id)
  }

  func scalars(_ glyphs: String...) -> [[Unicode.Scalar]] {
    glyphs.map { Array($0.unicodeScalars) }
  }

  func score(_ terms: [String], _ scalar: Unicode.Scalar, fuzzy: Bool = false) throws -> UInt8 {
    let scores = try index.scores(terms, fuzzy: fuzzy).scores
    return scores[try #require(index.scalars.firstIndex(of: scalar))]
  }

  static func missing(_ fonts: [FontConfiguration]) -> (Unicode.Scalar) -> Int {
    let probes = fonts.map(FontProbe.init)
    return { scalar in probes.count { $0.lacks(scalar) } }
  }

  @Test(arguments: [false, true])
  func leftArrowRanksLeftwardsArrowThenLeftRightArrow(withFonts: Bool) async throws {
    let results = try await ids("left arrow", fonts: withFonts ? fonts : [])
    #expect(Array(results.prefix(2)) == scalars("←", "↔"))
  }

  @Test func letterARanksTheLatinLettersFirst() async throws {
    #expect(Array(try await ids("letter a").prefix(2)) == scalars("a", "A"))
  }

  @Test func typosFallBackToFuzzyMatchingOnlyWhenNothingMatches() async throws {
    #expect(try await ids("letf arrow").contains(scalars("←")[0]))
    #expect(try await !ids("arrows").contains(scalars("←")[0]))
  }

  @Test func multiScalarGraphemesStillReachTheFuzzyLengthGate() async throws {
    let decomposedGha = "gh" + "a\u{301}"
    #expect(try await ids(decomposedGha).contains(scalars("\u{1A2}")[0]))
  }

  @Test func equivalentSpellingsFindTheSameCharacters() async throws {
    let bare = try await ids("0070")
    #expect(bare.first == scalars("p")[0])
    #expect(try await ids("u+0070") == bare)
    #expect(try await ids("U+0070") == bare)
    let words = try await ids("left arrow")
    #expect(!words.isEmpty)
    #expect(try await ids("left-arrow") == words)
    #expect(try await ids("left - arrow") == words)
    let flag = try await ids("flag")
    #expect(try await ids("flag:") == flag)
  }

  @Test(arguments: ["é", "π", "→", "©", "-", " ", "A", "a", "🦄", "👩‍🚀", "🇫🇷"])
  func aTypedCharacterComesFirstExactlyAsTyped(glyph: String) async throws {
    #expect(try await ids(glyph).first == scalars(glyph)[0])
  }

  @Test func caseInsensitiveMatchesFollowTheTypedCharacter() async throws {
    #expect(Array(try await ids("A").prefix(2)) == scalars("A", "a"))
    #expect(Array(try await ids(" A ").prefix(2)) == scalars("A", "a"))
    #expect(Array(try await ids("a").prefix(2)) == scalars("a", "A"))
    #expect(try await ids("a").count == CharacterSearchIndex.maximumResults)
  }

  @Test func combiningSequencesAreNotMergedWithPrecomposedCharacters() async throws {
    #expect(try await ids("e\u{301}") == scalars("e\u{301}"))
  }

  @Test func blankQueriesFindNothing() async throws {
    #expect(try await ids("").isEmpty)
    #expect(try await ids("   ").isEmpty)
  }

  @Test(arguments: [
    ("U+4E00", "\u{4E00}"), ("u+e000", "\u{E000}"), ("U+0007", "\u{7}"), ("U+FFFF", "\u{FFFF}"),
    ("0x1F600", "😀"), ("U+1F1EB U+1F1F7", "🇫🇷"), ("U+0031 U+FE0F U+20E3", "1️⃣"),
  ])
  func codePointsFindTheirCharacter(query: String, glyph: String) async throws {
    #expect(try await ids(query).first == scalars(glyph)[0])
    #expect(CharacterSearchIndex.codePointGlyph(query) != nil)
  }

  @Test(arguments: [
    "face", "1f600", "U+D800", "u+", "0x", "U++41", "U+0041 U+0042", "U+0041 arrow", "U+1234567",
    "U+" + String(repeating: "1", count: 17), "",
  ])
  func malformedCodePointsPinNothing(query: String) {
    #expect(CharacterSearchIndex.codePointGlyph(query) == nil)
  }

  @Test func hexTermsMatchPaddedCodePoints() async throws {
    #expect(CharacterSearchIndex.hexPattern("00041")! == (0x41, 5))
    #expect(CharacterSearchIndex.hexPattern("1234567") == nil)
    #expect(CharacterSearchIndex.hexPattern("g1") == nil)
    #expect(CharacterSearchIndex.hexContains(0x41, (0x41, 4)))
    #expect(!CharacterSearchIndex.hexContains(0x41, (0x41, 5)))
    #expect(CharacterSearchIndex.hexContains(0x1F1F7, (0xF1F7, 4)))
    #expect(!CharacterSearchIndex.hexContains(0x2190, (0x219, 4)))
    #expect(try await ids("2190").first == scalars("←")[0])
    #expect(Array(try await ids("4e2d").prefix(2)) == scalars("\u{1F22D}", "中"))
    #expect(try await ids("0x2190 arrow").first == scalars("←")[0])
    let hieroglyph = try await ids("a001")
    let wordMatch = try #require(hieroglyph.firstIndex(of: ["\u{13000}"]))
    let hexMatch = try #require(hieroglyph.firstIndex(of: ["\u{A001}"]))
    #expect(wordMatch < hexMatch)
  }

  @Test func termsScoreByTheirBestTier() throws {
    #expect(try score(["arrow"], "←") == 80)
    #expect(try score(["left"], "←") == 60)
    #expect(try score(["eftw"], "←") == 20)
    #expect(try score(["letf"], "←") == 0)
    #expect(try score(["letf"], "←", fuzzy: true) == 10)
    #expect(try score(["lft"], "←", fuzzy: true) == 0)
    #expect(try score(["left", "arrow"], "←") == 60)
    #expect(try score([], "←") == 0)
    #expect(try score(["gha"], "\u{1A2}") == 80)
    #expect(try score(["oi"], "\u{1A2}") == 80)
    #expect(try score(["bracket"], "\u{FE18}") == 80)
    #expect(try score(["brakcet"], "\u{FE18}") == 80)
  }

  @Test func editDistanceCountsOneInsertionDeletionSubstitutionOrTransposition() {
    func within(_ a: String, _ b: String) -> Bool {
      CharacterSearchIndex.withinOneEdit(a.unicodeScalars.map(\.value), Array(b.utf8)[...])
    }
    for (a, b) in [
      ("left", "left"), ("letf", "left"), ("lft", "left"), ("left", "lefts"),
      ("lefk", "left"), ("", "a"),
    ] {
      #expect(within(a, b), "\(a) → \(b)")
    }
    for (a, b) in [("", "abc"), ("abc", ""), ("abcd", "wxyz"), ("ab", "abcd"), ("abcd", "badc")] {
      #expect(!within(a, b), "\(a) → \(b)")
    }
    let word = Array("leftwards".utf8)
    for term in ["lefft", "letf", "lefw", "leftwarsd"] {
      #expect(CharacterSearchIndex.fuzzyMatch(word, term.unicodeScalars.map(\.value)), "\(term)")
    }
    #expect(!CharacterSearchIndex.fuzzyMatch(word, "right".unicodeScalars.map(\.value)))
  }

  @Test func singleWordsRankCommonCharactersBeforeShortNames() async throws {
    #expect(try await ids("latin").first == scalars("e")[0])
    #expect(Array(try await ids("check").prefix(1)) == scalars("✓"))
    let greek = try await ids("greek")
    let alpha = try #require(greek.firstIndex(of: scalars("α")[0]))
    #expect(greek.firstIndex(of: scalars("ϐ")[0]).map { alpha < $0 } != false)
    for variant: Unicode.Scalar in ["ϐ", "\u{1FBE}", "①", "\u{212B}"] {
      #expect(CharacterSearchIndex.isVariant(variant), "\(variant)")
    }
    for character: Unicode.Scalar in ["ﬁ", "‼", "é", "\u{2003}", "½"] {
      #expect(!CharacterSearchIndex.isVariant(character), "\(character)")
    }
  }

  @Test func equalMatchesRankByFontSupportThenPopularity() throws {
    let entries = [
      Entry(scalar: "\u{10B00}", name: "AVESTAN LETTER A", alias: nil),
      Entry(scalar: "\u{10B01}", name: "AVESTAN LETTER AA", alias: nil),
      Entry(scalar: "a", name: "LATIN SMALL LETTER A", alias: nil),
    ]
    let index = CharacterSearchIndex(entries: entries)
    func search(_ query: String, missing: Set<UInt32> = []) throws -> [String] {
      try index.search(query, fontCount: 1) { missing.contains($0.value) ? 1 : 0 }
    }
    #expect(try search("letter a") == ["a", "\u{10B00}", "\u{10B01}"])
    #expect(try search("avestan letter a") == ["\u{10B00}", "\u{10B01}"])
    #expect(try search("letter") == ["a", "\u{10B00}", "\u{10B01}"])
    #expect(try search("letter", missing: [0x61, 0x10B00]) == ["\u{10B01}", "a", "\u{10B00}"])
  }

  @Test func namelessCharactersAreFoundThroughAliases() throws {
    let index = CharacterSearchIndex(
      entries: [
        Entry(scalar: "—", name: nil, alias: "EMDASH"), Entry(scalar: "a", name: "A", alias: nil),
      ])
    #expect(try index.search("emdash", fontCount: 0) { _ in 0 } == ["—"])
  }

  @Test func placeholderNamesContributeNoWords() async throws {
    for value: UInt32 in [0x4E00, 0xF900, 0x17000, 0x18B00, 0x1B170] {
      let scalar = try #require(Unicode.Scalar(value))
      #expect(CharacterSearchIndex.isPlaceholder(try #require(scalar.properties.name), of: scalar))
    }
    for value: UInt32 in [0x18800, 0xFE0F, 0xAC00] {
      let scalar = try #require(Unicode.Scalar(value))
      #expect(!CharacterSearchIndex.isPlaceholder(try #require(scalar.properties.name), of: scalar))
    }
    for (row, scalar) in index.scalars.enumerated()
    where scalar.properties.name.map({ CharacterSearchIndex.isPlaceholder($0, of: scalar) }) ?? true
    {
      #expect(index.nameWordStarts[row] == index.nameWordStarts[row + 1])
    }
    for result in try await CharacterSearch.results(for: "ideograph", fonts: []) {
      let scalar = try #require(result.glyph.unicodeScalars.first)
      #expect(!CharacterSearchIndex.isPlaceholder(scalar.properties.name ?? "", of: scalar))
    }
  }

  @Test func hangulSyllablesAndSpacesAreFoundByName() async throws {
    #expect(try await ids("hangul syllable ga").first == scalars("가")[0])
    #expect(try await ids("space", fonts: fonts).first == scalars(" ")[0])
  }

  @Test func supportedFlagsMatchTheRenderer() async throws {
    let results = try await CharacterSearch.results(for: "arrow", fonts: fonts)
    #expect(!results.isEmpty)
    for result in results {
      #expect(result.supported == fonts.map { FontRenderer.supports(result.glyph, config: $0) })
    }
    #expect(results.contains { $0.supported == [false, true] })
    for query in ["U+1F1EB U+1F1F7", "e\u{301}", "👩‍🚀"] {
      let pinned = try #require(try await CharacterSearch.results(for: query, fonts: fonts).first)
      #expect(pinned.supported == fonts.map { FontRenderer.supports(pinned.glyph, config: $0) })
    }
  }

  @Test func invisibleAndFormatCharactersRankAsTheRendererJudgesThem() {
    let probes = fonts.map(FontProbe.init)
    #expect(probes.map { $0.lacks("←") } == [true, false])
    var checked = 0
    for scalar in index.scalars
    where scalar.properties.isDefaultIgnorableCodePoint
      || scalar.properties.generalCategory == .format
    {
      for (probe, config) in zip(probes, fonts) {
        #expect(probe.lacks(scalar) == !FontRenderer.supports(String(scalar), config: config))
      }
      checked += 1
    }
    #expect(checked > 100)
  }

  @Test func missingFontsNeitherRankNorSupportCharacters() async throws {
    let missing = [FontConfiguration("TypefaceOff-Does-Not-Exist")]
    let results = try await CharacterSearch.results(for: "letter a", fonts: missing)
    #expect(results.map(\.id) == (try await ids("letter a")))
    #expect(results.allSatisfy { $0.supported == [false] })
  }

  @Test func cancelledSearchesThrow() async {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await CharacterSearch.results(for: "arrow", fonts: [])
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test func theIndexCoversNamedCharactersWithASCIIWords() {
    #expect((40_000...70_000).contains(index.scalars.count))
    #expect(index.scalars.count { (0xAC00...0xD7A3).contains($0.value) } == 11_172)
    #expect(
      index.vocabulary.allSatisfy {
        $0.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x7A).contains($0) }
      })
    #expect(
      CharacterSearchIndex.words("  FLAG: left-ARROW ‹é› -  ") == ["flag", "left", "arrow", "é"])
    #expect(CharacterSearchIndex.terms("→") == ["→"])
  }

  @Test func optimizedSearchMatchesANaiveImplementation() throws {
    let platform = CharacterSearchIndex.platformEntries()
    let kept: Set<UInt32> = [
      0x61, 0x41, 0x65, 0x70, 0x2190, 0x2194, 0x2192, 0x1A2, 0xFE18, 0x20, 0x1F600, 0x4E2D,
    ]
    let entries = platform.enumerated().filter {
      $0.offset % 7 == 0 || kept.contains($0.element.scalar.value)
    }.map(\.element)
    let index = CharacterSearchIndex(entries: entries)
    let naive = NaiveCharacterSearch(entries: entries)
    for query in [
      "a", "e", "letter a", "left arrow", "letf arrow", "lefft", "u+0070", "0070", "face", "flag:",
      "→", "é", "gha", "bracket", "space", "1f600", "zzzz", "0x2190 arrow",
    ] {
      for fonts in [[], fonts] {
        let missing = Self.missing(fonts)
        let fast = try index.search(query, fontCount: fonts.count, missingFonts: missing)
        let slow = naive.search(query, fontCount: fonts.count, missingFonts: missing)
        #expect(
          fast.map { Array($0.unicodeScalars) } == slow.map { Array($0.unicodeScalars) }, "\(query)"
        )
      }
    }
  }
}

/// This file's straightforward restatement of the search rules, for checking the index.
private struct NaiveCharacterSearch {
  struct Row {
    let scalar: Unicode.Scalar
    let share: Double
    let variant: Bool
    let tier: UInt8
    let names: [String]
    let words: [String]
  }

  let rows: [Row]

  init(entries: [CharacterSearchIndex.Entry]) {
    rows = entries.map { entry in
      let names = CharacterSearchIndex.words(entry.name ?? "")
      return Row(
        scalar: entry.scalar, share: CharacterFrequency.table[entry.scalar] ?? 0,
        variant: CharacterSearchIndex.isVariant(entry.scalar),
        tier: CharacterSearchIndex.categoryTier(entry.scalar), names: names,
        words: names + CharacterSearchIndex.words(entry.alias ?? ""))
    }
  }

  func search(_ query: String, fontCount: Int, missingFonts: (Unicode.Scalar) -> Int)
    -> [String]
  {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let pin =
      query.count == 1
      ? query : trimmed.count == 1 ? trimmed : CharacterSearchIndex.codePointGlyph(trimmed)
    var results = pin.map { [$0] } ?? []
    guard !trimmed.isEmpty else { return results }
    let terms = CharacterSearchIndex.terms(trimmed)
    var matches = self.matches(terms, fuzzy: false, fontCount: fontCount, missing: missingFonts)
    if matches.isEmpty, terms.contains(where: { $0.unicodeScalars.count >= 4 }) {
      matches = self.matches(terms, fuzzy: true, fontCount: fontCount, missing: missingFonts)
    }
    let sorted = matches.sorted { $0.key.lexicographicallyPrecedes($1.key) }
    for match in sorted where results.count < 200 {
      if pin.map({ Array($0.unicodeScalars) }) != [match.scalar] {
        results.append(String(match.scalar))
      }
    }
    return results
  }

  private func matches(
    _ terms: [String], fuzzy: Bool, fontCount: Int, missing: (Unicode.Scalar) -> Int
  ) -> [(scalar: Unicode.Scalar, key: [Double])] {
    var result: [(scalar: Unicode.Scalar, key: [Double])] = []
    for row in rows {
      var score = 100
      var charHit = false
      for term in terms {
        let (tier, hit) = self.tier(term, row, fuzzy: fuzzy)
        score = min(score, tier)
        charHit = charHit || hit
      }
      guard score > 0 else { continue }
      let covered =
        terms.count > 1 ? row.names.count { name in terms.contains { name.hasPrefix($0) } } : 0
      let coverage = row.names.isEmpty ? 0 : Double(covered) / Double(row.names.count)
      let bucket = score == 100 ? 0 : score >= 60 ? 1 : score == 20 ? 2 : 3
      let lacking = missing(row.scalar)
      let unrenderable = fontCount > 0 && lacking == fontCount
      let leading = row.names.first.map { name in terms.contains { name.hasPrefix($0) } }
      let tier = row.tier >= 6 && leading != true ? 4 : row.tier
      result.append(
        (
          row.scalar,
          [
            Double(bucket), charHit ? 0 : 1, -coverage, Double(100 - score), unrenderable ? 1 : 0,
            -row.share, -Double(tier), row.variant ? 1 : 0, Double(lacking),
            Double(max(1, row.names.count)), Double(row.scalar.value),
          ]
        ))
    }
    return result
  }

  private func tier(_ term: String, _ row: Row, fuzzy: Bool) -> (Int, Bool) {
    var tier = 0
    var hit = false
    if Array(String(row.scalar).lowercased().unicodeScalars) == Array(term.unicodeScalars) {
      tier = 100
      hit = true
    }
    if row.words.contains(term) || row.words.contains(term + "s") { tier = max(tier, 80) }
    if row.words.contains(where: { $0.hasPrefix(term) }) { tier = max(tier, 60) }
    if row.words.contains(where: { $0.contains(term) }) { tier = max(tier, 20) }
    let digits = term.hasPrefix("u+") || term.hasPrefix("0x") ? String(term.dropFirst(2)) : term
    if (1...6).contains(digits.count), digits.allSatisfy({ "0123456789abcdef".contains($0) }),
      String(format: "%04x", row.scalar.value).contains(digits)
    {
      tier = max(tier, 20)
      if digits.count >= 4, UInt32(digits, radix: 16) == row.scalar.value { hit = true }
    }
    if fuzzy, tier == 0, term.count >= 4, row.words.contains(where: { Self.fuzzy($0, term) }) {
      tier = 10
    }
    return (tier, hit)
  }

  private static func fuzzy(_ word: String, _ term: String) -> Bool {
    let word = Array(word.unicodeScalars)
    let term = Array(term.unicodeScalars)
    if distance(term, word[...]) <= 1 { return true }
    return [term.count - 1, term.count, term.count + 1].contains { length in
      length < word.count && distance(term, word.prefix(length)) <= 1
    }
  }

  /// raycast-charp's optimal string alignment distance.
  private static func distance(_ a: [Unicode.Scalar], _ b: ArraySlice<Unicode.Scalar>) -> Int {
    let b = Array(b)
    var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count { d[i][0] = i }
    for j in 0...b.count { d[0][j] = j }
    for i in stride(from: 1, through: a.count, by: 1) {
      for j in stride(from: 1, through: b.count, by: 1) {
        d[i][j] = min(
          d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
          d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
        }
      }
    }
    return d[a.count][b.count]
  }
}
