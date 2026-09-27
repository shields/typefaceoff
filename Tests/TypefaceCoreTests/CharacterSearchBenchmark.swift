import Foundation
import Testing

@testable import TypefaceCore

extension SimilarityBenchmark {
  struct CharacterSearchTiming: Codable {
    let query: String
    let results: Int
    let secondsPerSearch: Double
  }

  struct CharacterSearchProfile: Codable {
    let entries: Int
    let words: Int
    let enumerationSeconds: Double
    let indexSeconds: Double
    let searches: [CharacterSearchTiming]
  }

  @Test(.benchmark)
  func profileCharacterSearch() async throws {
    let enumerationStart = ContinuousClock.now
    let entries = CharacterSearchIndex.platformEntries()
    let enumeration = seconds(since: enumerationStart)
    let indexStart = ContinuousClock.now
    let index = CharacterSearchIndex(entries: entries)
    let indexing = seconds(since: indexStart)
    #expect(index.scalars.count == CharacterSearchIndex.shared.scalars.count)
    let fonts = [FontConfiguration("HelveticaNeue"), FontConfiguration("ArialMT")]
    var searches: [CharacterSearchTiming] = []
    for query in ["left arrow", "a", "letf arrow", "U+2190", ""] {
      let expected = try await CharacterSearch.results(for: query, fonts: fonts)
      let start = ContinuousClock.now
      for _ in 0..<20 {
        #expect(try await CharacterSearch.results(for: query, fonts: fonts) == expected)
      }
      searches.append(
        CharacterSearchTiming(
          query: query, results: expected.count, secondsPerSearch: seconds(since: start) / 20))
    }
    try write(
      CharacterSearchProfile(
        entries: entries.count, words: index.vocabulary.count, enumerationSeconds: enumeration,
        indexSeconds: indexing, searches: searches),
      to: "character-search.json")
  }
}
