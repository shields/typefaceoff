import Foundation
import Testing

@testable import TypefaceCore

struct LanguageTests {
  @Test func bundledCatalogAndDefaults() throws {
    let database = LanguageDatabase.shared
    #expect(database.schema == 1)
    #expect(database.version == "0.8.1")
    #expect(database.languages.count == 705)
    #expect(database.languages.reduce(0) { $0 + $1.orthographies.count } == 757)
    var filter = LanguageFilter()
    let current = database.languages.filter(filter.includes)
    #expect(current.count == 108)
    #expect(current.reduce(0) { $0 + $1.orthographies(showHistorical: false).count } == 119)
    filter.showHistorical = true
    let historical = database.languages.filter(filter.includes)
    #expect(historical.count == 130)
    #expect(historical.reduce(0) { $0 + $1.orthographies.count } == 150)
    #expect(database.languages.filter(\.historical).count == 22)
    filter.query = "latin latn"
    #expect(!database.languages.filter(filter.includes).isEmpty)
    filter.query = "not-a-language"
    #expect(database.languages.filter(filter.includes).isEmpty)
    filter.clear()
    #expect(
      filter.minimumSpeakers == 0 && filter.showHistorical && filter.query == "not-a-language")
    filter.query = ""
    #expect(database.languages.allSatisfy(filter.includes))
    let english = try #require(database.languages.first { $0.id == "eng" })
    #expect(english.matches("ENG"))
    #expect(english.matches("English"))
    #expect(english.matches("Latin"))
    #expect(!english.matches("English Cyrillic"))
    #expect(english.isoName == "English")
    #expect(english.validity == "preliminary")
    #expect(english.speakersDate != nil)
    #expect(!english.sources.isEmpty)
    #expect(database.source.contains("hyperglot"))
    #expect(database.excluded["data confidence"] == 76)
    #expect(throws: (any Error).self) { try LanguageDatabase.decode(Data("{broken".utf8)) }
  }

  @Test func specimenPreservesInventoriesAndScalarIdentity() throws {
    let language = try Self.language()
    let orthography = language.orthographies[0]
    #expect(LanguageSpecimen.text(orthography, categories: [.base]) == "A a e\u{301} ch ◌\u{301}")
    #expect(
      LanguageSpecimen.text(orthography, categories: [.base, .numerals, .currency])
        == "A a e\u{301} ch ◌\u{301}\n\n0 1\n\n$")
    #expect(LanguageSpecimen.text(orthography, categories: [.punctuation]) == "")
    #expect(
      orthography[.base].tokens.map { Array($0.unicodeScalars) }.contains(
        Array("e\u{301}".unicodeScalars)))
    #expect(!orthography[.base].probes.contains { $0.text.contains("◌") })
    let composed = LanguageRequirement("é", sequence: false)
    let decomposed = LanguageRequirement("e\u{301}", sequence: false)
    #expect(composed != decomposed)
    #expect(Set([composed, decomposed]).count == 2)
    #expect(composed.id == composed)
    #expect(decomposed.text.unicodeScalars.elementsEqual("e\u{301}".unicodeScalars))
  }

  @Test func filtersUnknownSpeakersAndHistoricalOrthographies() throws {
    let language = try Self.language(speakers: nil)
    var filter = LanguageFilter()
    #expect(!filter.includes(language))
    filter.minimumSpeakers = 0
    #expect(filter.includes(language))
    let ancient = try Self.language(status: "historical", speakers: nil)
    #expect(!filter.includes(ancient))
    filter.showHistorical = true
    filter.minimumSpeakers = 8_300_000
    #expect(filter.includes(ancient))
    let oldOrthography = try Self.language(orthographies: [Self.orthography(status: "historical")])
    filter.showHistorical = false
    #expect(!filter.includes(oldOrthography))
    #expect(oldOrthography.orthographies[0].historical)
  }

  @Test func logarithmicSliderAndExactEntry() {
    #expect(SpeakerThreshold.position(0) == 0)
    #expect(SpeakerThreshold.position(100) == 1)
    #expect(SpeakerThreshold.position(1_000_000_000) == 8)
    #expect(SpeakerThreshold.value(0) == 0)
    #expect(SpeakerThreshold.value(0.99) == 0)
    #expect(SpeakerThreshold.value(1) == 100)
    #expect(SpeakerThreshold.value(9) == 1_000_000_000)
    #expect(SpeakerThreshold.value(SpeakerThreshold.position(8_300_000)) == 8_300_000)
    for (text, value) in [
      ("all", 0), ("0", 0), ("8.3M", 8_300_000), ("100K", 100_000), ("1B", 1_000_000_000),
      ("400", 400), ("1", 100), ("2B", 1_000_000_000),
    ] {
      #expect(SpeakerThreshold.parse(text) == value)
    }
    for text in ["", "no", "-1", "NaN", "inf", "1e309"] {
      #expect(SpeakerThreshold.parse(text) == nil)
    }
    for (value, text) in [
      (0, "All"), (100, "100"), (1_000, "1K"), (8_300_000, "8.3M"), (1_000_000_000, "1B"),
    ] {
      #expect(SpeakerThreshold.format(value) == text)
    }
  }

  @Test func coverageFilters() {
    #expect(
      LanguageCoverageFilter.options(comparing: true) == [.all, .both, .aOnly, .bOnly, .neither])
    #expect(LanguageCoverageFilter.options(comparing: false) == [.all, .covered, .incomplete])
    for filter in LanguageCoverageFilter.allCases {
      for a in [nil, true, false] as [Bool?] {
        for b in [nil, true, false] as [Bool?] {
          let expected: Bool
          switch filter {
          case .all: expected = true
          case .both: expected = a == true && b == true
          case .aOnly: expected = a == true && b == false
          case .bOnly: expected = a == false && b == true
          case .neither: expected = a == false && b == false
          case .covered: expected = a == true
          case .incomplete: expected = a == false
          }
          #expect(filter.includes(a: a, b: b) == expected)
        }
      }
    }
  }

  @Test func encodedRequirementsSequencesFallbackAndCache() async throws {
    let engine = LanguageCoverageEngine()
    let language = try Self.language()
    let missing = try Self.language(
      id: "missing", orthographies: [Self.orthography(base: "\u{10FFFF}", sequences: "a\u{10FFFF}")]
    )
    var font = FontConfiguration("ArialMT")
    let first = try await engine.results(for: [language, missing], font: font)
    let covered = try #require(first[language.id])
    #expect(covered.available)
    #expect(covered.complete(language))
    #expect(covered.completeScripts(language) == ["Latin"])
    let base = try #require(covered.orthographies[language.orthographies[0].id]?.categories[.base])
    #expect(base.required == 7 && base.covered == 7)
    let absent = try #require(
      first[missing.id]?.orthographies[missing.orthographies[0].id]?.categories[.base])
    #expect(absent.missing.count == 2 && absent.covered == 0)
    let count = await engine.probeCount
    font.leading = 40
    font.tracking = 0.1
    _ = try await engine.results(for: [language], font: font)
    #expect(await engine.probeCount == count)
    #expect(await engine.cachedConfigurationCount == 1)
    font.size = 30
    font.features["ot.liga"] = 0
    _ = try await engine.results(for: [language], font: font)
    #expect(await engine.cachedConfigurationCount == 2)
    let unavailable = try await engine.results(
      for: [language], font: FontConfiguration("MissingLanguageFont"))
    #expect(unavailable[language.id]?.available == false)
    #expect(unavailable[language.id]?.completeScripts(language).isEmpty == true)
    _ = try await engine.results(for: [], font: font)
    for size in 31...35 {
      font.size = Double(size)
      _ = try await engine.results(for: [language], font: font)
    }
    #expect(await engine.cachedConfigurationCount == 4)
  }

  @Test func groupsAlternativesAndHistoricalPolicy() async throws {
    let good = Self.orthography(id: "good", base: "A", grouped: true)
    let bad = Self.orthography(id: "bad", base: "\u{10FFFF}", grouped: true)
    let group = try Self.language(id: "group", orthographies: [good, bad])
    let alternatives = try Self.language(
      id: "alternatives",
      orthographies: [
        Self.orthography(id: "bad", base: "\u{10FFFF}"), Self.orthography(id: "good", base: "A"),
      ])
    let historical = try Self.language(
      id: "history",
      orthographies: [
        Self.orthography(id: "bad", base: "\u{10FFFF}"),
        Self.orthography(id: "old", status: "historical", base: "A"),
      ])
    let ancient = try Self.language(
      id: "ancient", status: "historical",
      orthographies: [Self.orthography(status: "historical", base: "A")])
    let groupedGood = try Self.language(id: "grouped-good", orthographies: [good])
    let engine = LanguageCoverageEngine()
    let results = try await engine.results(
      for: [group, alternatives, historical, ancient, groupedGood], font: .init("ArialMT"))
    #expect(results[group.id]?.complete(group) == false)
    #expect(results[alternatives.id]?.complete(alternatives) == true)
    #expect(results[historical.id]?.complete(historical) == false)
    #expect(results[ancient.id]?.complete(ancient) == true)
    #expect(results[groupedGood.id]?.complete(groupedGood) == true)
  }

  @Test func prioritizedProgressAndCancellation() async throws {
    let database = LanguageDatabase.shared
    let engine = LanguageCoverageEngine()
    let progress = LanguageProgress()
    let results = try await engine.results(
      for: database.languages, font: .init("ArialMT"), priority: ["eng", "eng", "jpn"]
    ) { partial in
      await progress.record(partial)
    }
    #expect(await progress.first == ["eng"])
    #expect(results.count == 705)
    let english = try #require(database.languages.first { $0.id == "eng" })
    #expect(results["eng"]?.complete(english) == true)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await engine.results(for: database.languages, font: .init("ArialMT"))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    _ = try await LanguageCoverageEngine.shared.results(for: [], font: .init("ArialMT"))
  }

  static func orthography(
    id: String = "latin", status: String = "primary", base: String = "A a e h c \u{301}",
    sequences: String = "e\u{301}", grouped: Bool = false
  ) -> [String: Any] {
    let categories = Dictionary(
      uniqueKeysWithValues: LanguageCategory.allCases.map { category in
        let characters =
          category == .base
          ? "A a e\u{301} ch ◌\u{301}"
          : category == .numerals ? "0 1" : category == .currency ? "$" : ""
        return (
          category.rawValue,
          [
            "characters": characters, "requirements": category == .base ? base : characters,
            "sequences": category == .base ? sequences : "",
          ]
        )
      })
    return [
      "id": id, "script": "Latin", "scriptCode": "Latn", "status": status, "autonym": "Example",
      "grouped": grouped, "categories": categories, "notes": [String](),
    ]
  }

  static func language(
    id: String = "example", status: String = "living", speakers: Int? = 9_000_000,
    orthographies: [[String: Any]]? = nil
  ) throws -> LanguageRecord {
    let language: [String: Any] = [
      "id": id, "name": "Example", "isoName": "Example", "status": status, "validity": "verified",
      "speakers": speakers as Any? ?? NSNull(), "speakersDate": "2020", "autonyms": ["Example"],
      "orthographies": orthographies ?? [Self.orthography()], "notes": [String](),
      "sources": [String](), "contributors": [String](), "reviewers": [String](),
    ]
    let data = try JSONSerialization.data(withJSONObject: [
      "schema": 1, "version": "test", "source": "test", "excluded": [String: Int](),
      "languages": [language],
    ])
    return try LanguageDatabase.decode(data).languages[0]
  }
}

private actor LanguageProgress {
  var first: [String]?
  func record(_ partial: [String: LanguageCoverage]) {
    if first == nil { first = partial.keys.sorted() }
  }
}
