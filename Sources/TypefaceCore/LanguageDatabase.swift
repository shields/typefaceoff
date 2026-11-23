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

public enum LanguageCategory: String, CaseIterable, Codable, Sendable {
  case base, auxiliary, numerals, punctuation, currency
}

public struct LanguageInventory: Decodable, Sendable {
  public let characters: String
  public let requirements: String
  public let sequences: String

  public var tokens: [String] { Self.split(characters) }
  public var probes: [LanguageRequirement] {
    Self.split(requirements).map { LanguageRequirement($0, sequence: false) }
      + Self.split(sequences).map { LanguageRequirement($0, sequence: true) }
  }

  private static func split(_ text: String) -> [String] {
    text.unicodeScalars.split(separator: " ").map { String(String.UnicodeScalarView($0)) }
  }
}

public struct LanguageRequirement: Hashable, Sendable, Identifiable {
  public let scalars: [Unicode.Scalar]
  public let sequence: Bool
  public var id: Self { self }
  public var text: String { String(String.UnicodeScalarView(scalars)) }

  public init(_ text: String, sequence: Bool) {
    scalars = Array(text.unicodeScalars)
    self.sequence = sequence
  }
}

public struct OrthographyRecord: Decodable, Identifiable, Sendable {
  public let id: String
  public let script: String
  public let scriptCode: String
  public let status: String
  public let autonym: String
  public let grouped: Bool
  public let categories: [String: LanguageInventory]
  public let notes: [String]
  public var historical: Bool { status == "historical" }

  public subscript(_ category: LanguageCategory) -> LanguageInventory {
    categories[category.rawValue]!
  }
}

public struct LanguageRecord: Decodable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let isoName: String
  public let status: String
  public let validity: String
  public let speakers: Int?
  public let speakersDate: String?
  public let autonyms: [String]
  public let orthographies: [OrthographyRecord]
  public let notes: [String]
  public let sources: [String]
  public let contributors: [String]
  public let reviewers: [String]
  public var historical: Bool { status == "historical" }

  public func orthographies(showHistorical: Bool) -> [OrthographyRecord] {
    orthographies.filter { showHistorical || !$0.historical }
  }

  public func matches(_ query: String) -> Bool {
    let words = query.split(whereSeparator: \.isWhitespace)
    let fields =
      [name, isoName, id] + autonyms
      + orthographies.flatMap { [$0.script, $0.scriptCode] }
    return words.allSatisfy { word in
      fields.contains { $0.localizedStandardContains(word) }
    }
  }
}

public struct LanguageDatabase: Decodable, Sendable {
  public let schema: Int
  public let version: String
  public let source: String
  public let excluded: [String: Int]
  public let languages: [LanguageRecord]

  public static let shared: Self = {
    let url = Bundle.module.url(forResource: "languages", withExtension: "json")!
    let database = try! Self.decode(Data(contentsOf: url))
    precondition(database.schema == 1)
    return database
  }()

  public static func decode(_ data: Data) throws -> Self {
    let database = try JSONDecoder().decode(Self.self, from: data)
    precondition(Set(database.languages.map(\.id)).count == database.languages.count)
    precondition(
      database.languages.allSatisfy { language in
        !language.orthographies.isEmpty
          && language.orthographies.allSatisfy { orthography in
            LanguageCategory.allCases.allSatisfy { orthography.categories[$0.rawValue] != nil }
              && !orthography[.base].tokens.isEmpty
          }
      })
    return Self(
      schema: database.schema, version: database.version, source: database.source,
      excluded: database.excluded,
      languages: database.languages.sorted {
        let comparison = $0.name.compare(
          $1.name, options: [.caseInsensitive, .diacriticInsensitive])
        return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
      })
  }
}

public struct LanguageFilter: Equatable, Sendable {
  public var minimumSpeakers = 8_300_000
  public var showHistorical = false
  public var query = ""

  public init() {}

  public func includes(_ language: LanguageRecord) -> Bool {
    guard showHistorical || !language.historical else { return false }
    guard !language.orthographies(showHistorical: showHistorical).isEmpty else { return false }
    return
      (minimumSpeakers == 0 || language.historical || (language.speakers ?? 0) >= minimumSpeakers)
      && language.matches(query)
  }

  public mutating func clear() {
    minimumSpeakers = 0
    showHistorical = true
  }
}

public enum SpeakerThreshold {
  public static func position(_ value: Int) -> Double {
    value == 0 ? 0 : log10(Double(value.clamped(to: 100...1_000_000_000))) - 1
  }

  public static func value(_ position: Double) -> Int {
    position < 1 ? 0 : Int(pow(10, position.clamped(to: 1...8) + 1).rounded())
  }

  public static func parse(_ text: String) -> Int? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if text == "ALL" || text == "0" { return 0 }
    let suffix = text.last
    let multiplier: Double = suffix == "K" ? 1_000 : suffix == "M" ? 1_000_000 : 1
    let number = multiplier == 1 ? text : String(text.dropLast())
    guard let value = Double(number), value.isFinite, value > 0 else { return nil }
    return Int((value * multiplier).clamped(to: 100...1_000_000_000).rounded())
  }

  public static func format(_ value: Int) -> String {
    if value == 0 { return "All" }
    let divisor = value >= 1_000_000 ? 1_000_000 : value >= 1_000 ? 1_000 : 1
    let suffix = divisor == 1_000_000 ? "M" : divisor == 1_000 ? "k" : ""
    return (Double(value) / Double(divisor)).formatted(
      .number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3))) + suffix
  }
}

extension Int {
  fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
    Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
  }
}

public enum LanguageSpecimen {
  public static func text(_ orthography: OrthographyRecord, categories: Set<LanguageCategory>)
    -> String
  {
    LanguageCategory.allCases.filter { categories.contains($0) }.map {
      orthography[$0].characters
    }.filter { !$0.isEmpty }.joined(separator: "\n\n")
  }
}
