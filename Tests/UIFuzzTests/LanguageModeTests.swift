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

@testable import UIFuzzSupport

struct LanguageModeTests {
  @Test func languageControlsRestoreTheirMode() {
    for target in [
      "Language row eng", "Language speaker field", "Language list scroll area",
      "Inspect language U+0041", "Search Languages", "Show historical", "Minimum speaker count",
      "Minimum language speakers",
      "Use Checked as Specimen", "Clear Filters",
    ] {
      let action = FuzzAction(kind: .press, target: target)
      let requirement = WorkbenchState.requirement(of: action)
      #expect(requirement == .mode(.languages))
      var state = WorkbenchState.launch
      let enablers = state.enable(.mode(.languages))
      #expect(enablers.count == 1 && enablers[0].keyCode == 20)
      #expect(state.satisfies(.mode(.languages)))
    }
    var state = WorkbenchState.launch
    state.apply(FuzzAction(kind: .press, target: "Languages"))
    #expect(state.mode == .languages)
    for target in ["Search Languages"] {
      state.apply(FuzzAction(kind: .setValue, target: target, value: "English"))
      #expect(state.mode == .languages && state.popover == .closed)
    }
    state.apply(FuzzAction(kind: .press, target: "Language use specimen button"))
    #expect(state.mode == .text)
    state.apply(FuzzAction(kind: .shortcut, keyCode: 20, modifiers: 1 << 20))
    state.apply(FuzzAction(kind: .press, target: "Inspect language U+0041"))
    #expect(state.mode == .glyph)
    state.apply(FuzzAction(kind: .shortcut, keyCode: 20, modifiers: 1 << 20))
    state.apply(
      FuzzAction(kind: .press, target: "Language missing eng/0/Latn/primary base 41 false 0"))
    #expect(state.mode == .glyph)
  }

  @Test func languageInputsExploreNamesAndSpeakerUnits() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 100)
    for target in [
      "Search Languages", "Language speaker field",
      "Minimum speaker count", "Minimum language speakers",
    ] {
      var values: Set<String> = []
      for _ in 0..<128 {
        let action = explorer.next(
          from: [FuzzAction(kind: .setValue, target: target)], using: &random)
        values.insert(action.value!)
      }
      if target == "Search Languages" {
        #expect(values.contains("eng") && values.contains("Ancient Greek"))
      } else {
        #expect(values.contains("All") && values.contains("8.3M") && values.contains("100k"))
      }
    }
  }
}
