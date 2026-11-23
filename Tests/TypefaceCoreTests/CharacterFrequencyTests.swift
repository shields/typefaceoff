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

import Darwin
import Foundation
import Testing

@testable import TypefaceCore

@Suite(.serialized) struct CharacterFrequencyTests {
  @Test(arguments: ["", "\u{200D}", "\u{FE0F}", "\u{E0100}"])
  func emptyAndFormattingOnlyGraphemesHaveNoFrequency(grapheme: String) {
    #expect(CharacterFrequency.frequency(of: grapheme) == nil)
  }
  @Test func tableLoadsAndIsNonEmptyAndSortedByDescendingShare() {
    let shares = CharacterFrequency.parseEntries(CharacterFrequency.resourceContents()).map(\.1)
    #expect(!shares.isEmpty)
    #expect(shares == shares.sorted(by: >))
    #expect(CharacterFrequency.table.count == shares.count)
  }

  @Test func generatedTableIsTruncatedAtTheWeightFloor() throws {
    let smallest = try #require(CharacterFrequency.table.values.min())
    #expect(smallest >= CharacterFrequency.floor)
    #expect(smallest < CharacterFrequency.floor * 1.05)
  }

  @Test func parsingAcceptsCRLFLineEndings() {
    let entries = CharacterFrequency.parseEntries("# comment\r\n0065\t5.1e-02\r\n0040\t3.9e-05\r\n")
    #expect(entries.map(\.0) == ["e", "@"])
    #expect(entries.map(\.1) == [5.1e-02, 3.9e-05])
  }

  @Test func commonLettersSaturateToFullWeight() {
    #expect(CharacterFrequency.weight(forFrequency: CharacterFrequency.frequency(of: "e")) == 1)
  }

  @Test func aMidFrequencySymbolIsPartiallyDiscounted() {
    let weight = CharacterFrequency.weight(forFrequency: CharacterFrequency.frequency(of: "@"))
    #expect(weight > 0.1 && weight < 1)
  }

  @Test func absentCharactersHaveNilFrequencyAndTheFloorWeight() {
    #expect(CharacterFrequency.frequency(of: "\u{E000}") == nil)
    #expect(CharacterFrequency.weight(forFrequency: nil) == 0.1)
  }

  @Test func combiningSequencesMatchTheirPrecomposedEquivalent() {
    #expect(CharacterFrequency.frequency(of: "e\u{301}") == CharacterFrequency.frequency(of: "é"))
  }

  @Test func multiScalarClustersFollowTheMinimumOverScalarsRule() {
    let conjunct = "\u{915}\u{94D}\u{937}"  // Devanagari क्ष, not NFC-composable.
    let expected = min(
      CharacterFrequency.table[Unicode.Scalar(0x915)!]!,
      CharacterFrequency.table[Unicode.Scalar(0x94D)!]!,
      CharacterFrequency.table[Unicode.Scalar(0x937)!]!)
    #expect(CharacterFrequency.frequency(of: conjunct) == expected)
    // The joiner is ignored, and both emoji are below the table's floor.
    #expect(CharacterFrequency.frequency(of: "👩‍🚀") == nil)
  }

  @Test func weightIsMonotonicInFrequency() {
    let shares: [Double?] = [nil, 1e-6, 1e-5, 3e-5, 1e-4, 5e-4, 1e-3, 1e-2, 1]
    let weights = shares.map { CharacterFrequency.weight(forFrequency: $0) }
    #expect(weights == weights.sorted())
  }

  @Test func missingResourceFailsFast() async {
    Self.preserveExitCoverage()
    await #expect(processExitsWith: .failure) {
      _ = CharacterFrequency.resourceContents(name: "does-not-exist")
    }
  }

  @Test func malformedLineFailsFast() async {
    Self.preserveExitCoverage()
    await #expect(processExitsWith: .failure) {
      _ = CharacterFrequency.parseEntries("00XY\tnot-a-number\n")
    }
  }

  @Test func emptyTableFailsFast() async {
    Self.preserveExitCoverage()
    await #expect(processExitsWith: .failure) {
      _ = CharacterFrequency.parseEntries("# only a comment\n")
    }
  }

  @Test func missingFrequencyFailsFast() async {
    Self.preserveExitCoverage()
    await #expect(processExitsWith: .failure) {
      _ = CharacterFrequency.parseEntries("0065\n")
    }
  }

  private static func preserveExitCoverage() {
    guard let value = getenv("LLVM_PROFILE_FILE") else { return }
    let pattern = String(cString: value)
    guard !pattern.contains("%c") else { return }
    let path = URL(filePath: pattern).deletingPathExtension().path + "%c.profraw"
    precondition(setenv("LLVM_PROFILE_FILE", path, 1) == 0)
  }
}
