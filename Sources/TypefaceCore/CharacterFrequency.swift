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

/// Per-character shares of a global, speaker-weighted language mix (see
/// `docs/character-frequency.md`), used to weight difference rankings toward
/// characters people actually encounter.
public enum CharacterFrequency {
  /// Characters at or above this share weight fully: seen roughly once per
  /// thousand characters or more often.
  public static let saturation = 1e-3
  /// The table omits characters below this share; absent characters are
  /// treated as this rare rather than infinitely rare.
  public static let floor = 1e-5

  static let table = Dictionary(uniqueKeysWithValues: parseEntries(resourceContents()))

  /// The minimum share among `grapheme`'s scalars, ignoring format characters
  /// (general category Cf) and variation selectors, which FineFreq does not
  /// tabulate. `nil` when no scalar remains or the table lacks one.
  public static func frequency(of grapheme: String) -> Double? {
    let scalars = grapheme.precomposedStringWithCanonicalMapping.unicodeScalars.filter {
      $0.properties.generalCategory != .format && !isVariationSelector($0)
    }
    guard !scalars.isEmpty else { return nil }
    var minimum = Double.infinity
    for scalar in scalars {
      guard let p = table[scalar] else { return nil }
      minimum = min(minimum, p)
    }
    return minimum
  }

  /// A character seen at least once per thousand counts fully; rarer
  /// characters, including ones missing from the table, are discounted by the
  /// square root of how much rarer they are, at most tenfold.
  public static func weight(forFrequency p: Double?) -> Double {
    ((p ?? 0).clamped(to: floor...saturation) / saturation).squareRoot()
  }

  private static func isVariationSelector(_ scalar: Unicode.Scalar) -> Bool {
    (0xFE00...0xFE0F).contains(scalar.value) || (0xE0100...0xE01EF).contains(scalar.value)
  }

  static func resourceContents(name: String = "character-frequencies") -> String {
    let url = Bundle.module.url(forResource: name, withExtension: "tsv")
    precondition(url != nil)
    return try! String(contentsOf: url!, encoding: .utf8)
  }

  static func parseEntries(_ contents: String) -> [(Unicode.Scalar, Double)] {
    let lines = contents.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("#") }
    let entries = lines.map { line in
      let fields = line.split(separator: "\t")
      let scalar = fields.first.flatMap { UInt32($0, radix: 16) }.flatMap { Unicode.Scalar($0) }
      let p = fields.count == 2 ? Double(fields[1]) : nil
      precondition(scalar != nil && p != nil)
      return (scalar!, p!)
    }
    precondition(!entries.isEmpty)
    return entries
  }
}
