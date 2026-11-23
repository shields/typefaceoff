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

import Testing

@testable import TypefaceCore

@Suite struct PairedFontFeaturesTests {
  private func feature(_ id: String, defaultValue: Int = 0) -> FontFeature {
    FontFeature(
      id: id, name: "Ligatures",
      options: [.init(name: "Off", value: 0), .init(name: "On", value: 1)],
      defaultValue: defaultValue)
  }

  @Test func identifiersKeepAATAndOpenTypeDistinctAndPreserveFontOrder() {
    let aat = feature("aat.1.2", defaultValue: 1)
    let ot = feature("ot.liga")
    let kern = feature("ot.kern", defaultValue: 1)
    let rows = PairedFontFeature.rows(a: [aat, kern], b: [ot, kern])
    #expect(rows.map(\.id) == [aat.id, kern.id, ot.id])
    #expect(rows[0][.a] == aat && rows[0][.b] == nil)
    #expect(rows[1][.a] == kern && rows[1][.b] == kern)
    #expect(rows[2].feature == ot && rows[2][.a] == nil)
    #expect(PairedFontFeature.rows(a: [], b: []).isEmpty)
  }

  @Test func defaultsDifferencesAndMissingFeatures() {
    let feature = feature("ot.liga", defaultValue: 1)
    let shared = PairedFontFeature.rows(a: [feature], b: [feature])[0]
    #expect(!shared.isChanged(a: [:], b: [:]) && !shared.differs(a: [:], b: [:]))
    #expect(shared.isChanged(a: [feature.id: 0], b: [:]))
    #expect(shared.isChanged(a: [:], b: [feature.id: 0]))
    #expect(shared.differs(a: [:], b: [feature.id: 0]))
    #expect(!shared.differs(a: [feature.id: 0], b: [feature.id: 0]))
    for row in [
      PairedFontFeature.rows(a: [feature], b: [])[0],
      PairedFontFeature.rows(a: [], b: [feature])[0],
    ] {
      #expect(!row.differs(a: [:], b: [:]))
      #expect(row.differs(a: [feature.id: 0], b: [feature.id: 0]))
    }
    let differentDefaults = PairedFontFeature.rows(a: [feature], b: [self.feature("ot.liga")])[0]
    #expect(differentDefaults.differs(a: [:], b: [:]))
    #expect(!differentDefaults.isChanged(a: [:], b: [:]))
  }
}
