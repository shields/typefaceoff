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

import Foundation
import Testing

@testable import TypefaceCore

struct LanguagePresentationTests {
  @Test func cellsKeepCombiningSequencesAndSeparatePunctuation() throws {
    let language = try LanguageTests.language()
    let cells = LanguagePresentation.cells(language.orthographies[0][.base])
    #expect(cells == ["A", "a", "e\u{301}", "c", "h", "◌\u{301}"])
    #expect(cells[2].unicodeScalars.elementsEqual("e\u{301}".unicodeScalars))
  }

  @Test func displayCountsRoundWithoutChangingTheThreshold() {
    for (count, expected) in [
      (920_000_000, "920M"), (76_800_000, "77M"), (8_300_000, "8M"),
      (250_400, "250k"), (999, "999"), (0, "0"),
    ] {
      #expect(LanguagePresentation.speakers(count) == expected)
    }
    #expect(LanguagePresentation.speakers(nil) == "—")
    #expect(SpeakerThreshold.format(8_300_000) == "8.3M")
  }

  @Test func sortingUsesExactCountsAndStableNames() throws {
    let larger = try LanguageTests.language(id: "z", speakers: 8_400_000)
    let smaller = try LanguageTests.language(id: "a", speakers: 8_300_000)
    let unknown = try LanguageTests.language(id: "unknown", speakers: nil)
    let languages = [smaller, unknown, larger]
    var order = LanguageOrdering()
    #expect(order.sorted(languages, a: [:], b: [:]).map(\.id) == ["z", "a", "unknown"])
    order.select(.speakers)
    #expect(order.sorted(languages, a: [:], b: [:]).map(\.id) == ["unknown", "a", "z"])
    order.select(.language)
    #expect(order.ascending)
    #expect(order.sorted(languages, a: [:], b: [:]).map(\.id) == ["a", "unknown", "z"])
    let catalog = LanguageDatabase.shared.languages
    let english = try #require(catalog.first { $0.id == "eng" })
    let german = try #require(catalog.first { $0.id == "deu" })
    #expect(order.sorted([german, english], a: [:], b: [:]).map(\.id) == ["eng", "deu"])
    order.select(.language)
    #expect(order.sorted([english, german], a: [:], b: [:]).map(\.id) == ["deu", "eng"])
    order.select(.speakers)
    #expect(order.sorted([smaller, smaller], a: [:], b: [:]).count == 2)
    let equal = try LanguageTests.language(id: "b", speakers: 8_300_000)
    #expect(order.sorted([equal, smaller], a: [:], b: [:]).map(\.id) == ["a", "b"])
  }

  @Test func coverageOrderingDistinguishesPendingUnavailableAndIncomplete() throws {
    let records = try (0..<4).map { try LanguageTests.language(id: String($0)) }
    let unavailable = LanguageCoverage(available: false, orthographies: [:])
    let incomplete = LanguageCoverage(
      available: true,
      orthographies: [
        "latin": OrthographyCoverage(categories: [
          .base: InventoryCoverage(required: 1, missing: [.init("A", sequence: false)])
        ])
      ])
    let complete = LanguageCoverage(
      available: true,
      orthographies: [
        "latin": OrthographyCoverage(categories: [
          .base: InventoryCoverage(required: 1, missing: [])
        ])
      ])
    let coverage = ["1": unavailable, "2": incomplete, "3": complete]
    #expect(
      records.map { LanguageCoverageMark(coverage[$0.id], language: $0).title } == [
        "Checking", "Font unavailable", "Incomplete", "Complete",
      ])
    for column in [LanguageColumn.a, .b] {
      var order = LanguageOrdering()
      order.select(column)
      #expect(order.sorted(records, a: coverage, b: coverage).map(\.id) == ["3", "2", "1", "0"])
      order.select(column)
      #expect(order.sorted(records, a: coverage, b: coverage).map(\.id) == ["0", "1", "2", "3"])
    }
  }

  @Test func factsKeepDistinctAutonymsAndScriptRequirements() throws {
    let catalog = LanguageDatabase.shared.languages
    let english = try #require(catalog.first { $0.id == "eng" })
    let german = try #require(catalog.first { $0.id == "deu" })
    #expect(!LanguagePresentation.facts(english).contains("English"))
    #expect(LanguagePresentation.facts(german).contains("Deutsch"))
    #expect(LanguagePresentation.facts(english).contains("400,000,000 speakers (2006)"))
    let historical = try LanguageTests.language(
      status: "historical", speakers: nil,
      orthographies: [
        LanguageTests.orthography(status: "historical", grouped: true)
      ])
    #expect(LanguagePresentation.facts(historical).contains("Speaker count unknown"))
    #expect(LanguagePresentation.facts(historical).hasSuffix("Historical"))
    #expect(
      LanguagePresentation.script(historical.orthographies[0])
        == "Latin (Latn) · Historical · Required group")
    #expect(LanguagePresentation.script(english.orthographies[0]) == "Latin (Latn)")
    let withoutDate = LanguageRecord(
      id: "a", name: "Name", isoName: "Name", status: "living",
      validity: "verified", speakers: 1, speakersDate: nil, autonyms: ["", "name", "Autonym"],
      orthographies: [], notes: [], sources: [], contributors: [], reviewers: [])
    #expect(LanguagePresentation.facts(withoutDate) == "a · Autonym · 1 speakers · verified data")
  }
}
