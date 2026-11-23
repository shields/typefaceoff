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

@Suite struct SpecificationNumberTests {
  let locale = Locale(identifier: "en_US")

  @Test(arguments: [
    ([22.0, 22.0], 0, ["22", "22"]),
    ([22.0, 21.5], 1, ["22.0", "21.5"]),
    ([22.0, 21.46], 2, ["22.00", "21.46"]),
    ([0.0, 0.004], 3, ["0.000", "0.004"]),
    ([9.5, 22.0], 1, ["9.5", "22.0"]),
    ([21.459_999_999], 2, ["21.46"]),
    ([21.4567], 3, ["21.457"]),
    ([-0.0001, 0.0], 0, ["0", "0"]),
    ([], 0, []),
  ])
  func pairedPrecision(values: [Double], digits: Int, expected: [String]) {
    let precision = SpecificationNumber.precision(values)
    #expect(precision == digits)
    #expect(
      values.map { SpecificationNumber.format($0, precision: precision, locale: locale) }
        == expected)
  }

  @Test func computedValuesForceThreeDecimals() {
    let precision = SpecificationNumber.precision([28, 25.720], computed: true)
    #expect(precision == 3)
    #expect(SpecificationNumber.format(28, precision: precision, locale: locale) == "28.000")
    #expect(SpecificationNumber.format(25.720, precision: precision, locale: locale) == "25.720")
    #expect(SpecificationNumber.format(-0.0001, precision: 3, locale: locale) == "0.000")
    #expect(SpecificationNumber.format(2048, precision: 0, locale: locale) == "2048")
  }

  @Test func defaultLocaleRoundTrips() {
    let text = SpecificationNumber.format(22.5, precision: 1)
    #expect(SpecificationNumber.parse(text) == 22.5)
    #expect(SpecificationValue(range: 10...144, step: 1).entry(text) == .number(22.5))
  }

  @Test func invalidSteppingConfigurationFailsFast() async {
    if let profile = getenv("LLVM_PROFILE_FILE") {
      let pattern = String(cString: profile)
      if !pattern.contains("%c") {
        precondition(setenv("LLVM_PROFILE_FILE", pattern + "%c", 1) == 0)
      }
    }
    await #expect(processExitsWith: .failure) {
      _ = SpecificationValue(range: 10...144, step: 0)
    }
  }

  @Test(arguments: ["en_US", "fr_FR", "de_DE", "ar_EG"])
  func localizedNumbersRoundTrip(identifier: String) {
    let locale = Locale(identifier: identifier)
    let value = SpecificationNumber.format(-0.004, precision: 3, locale: locale)
    #expect(SpecificationNumber.parse(value, locale: locale) == -0.004)
    #expect(SpecificationNumber.parse(" 22 \n", locale: locale) == 22)
  }

  @Test(arguments: ["", " ", "invalid", "22garbage", "NaN", "∞", "-∞", "22 pt", "1,000"])
  func invalidNumbersAreRejected(text: String) {
    #expect(SpecificationNumber.parse(text, locale: locale) == nil)
  }

  @Test func entriesRejectOutOfRangeValuesAndOnlyLeadingAcceptsAnEmptyField() {
    let size = SpecificationValue(range: 10...144, step: 1)
    for text in ["", "9.999", "144.001", "NaN", "no"] {
      #expect(size.entry(text, locale: locale) == nil)
    }
    #expect(size.entry("10", locale: locale) == .number(10))
    #expect(size.entry("144", locale: locale) == .number(144))
    #expect(size.entry("21.46", locale: locale) == .number(21.46))
    let leading = SpecificationValue(range: 1...288, step: 1, allowsAutomatic: true)
    #expect(leading.entry(" \n", locale: locale) == .automatic)
    #expect(leading.entry("28", locale: locale) == .number(28))
    #expect(leading.entry("auto", locale: locale) == nil)
    #expect(leading.entry("0", locale: locale) == nil)
    #expect(leading.entry("289", locale: locale) == nil)
  }

  @Test func keyboardSteppingUsesModifiersAndStopsAtTheRange() {
    let size = SpecificationValue(range: 10...144, step: 1)
    #expect(size.stepping(22, direction: 1) == 23)
    #expect(size.stepping(22, direction: -1) == 21)
    #expect(size.stepping(22, direction: 1, shift: true) == 32)
    #expect(size.stepping(22, direction: -1, option: true) == 21.9)
    #expect(size.stepping(22, direction: 1, shift: true, option: true) == 23)
    #expect(size.stepping(143.9, direction: 1) == 144)
    #expect(size.stepping(10, direction: -1) == 10)
    let tracking = SpecificationValue(range: -0.12...0.15, step: 0.001)
    #expect(tracking.stepping(0.004, direction: -1) == 0.003)
    #expect(tracking.stepping(0, direction: 1, option: true) == 0.0001)
    #expect(tracking.stepping(0.14, direction: 1, shift: true) == 0.15)
  }
}
