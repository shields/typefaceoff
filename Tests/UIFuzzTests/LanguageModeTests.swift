import Testing

@testable import UIFuzzSupport

struct LanguageModeTests {
  @Test func languageControlsRestoreTheirMode() {
    for target in [
      "Language row eng", "Language speaker field", "Language list scroll area",
      "Inspect language U+0041", "Search languages", "Show historical", "Minimum speaker count",
      "Minimum language speakers",
      "Use as specimen", "Clear filters",
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
    for target in ["Language search field", "Search languages"] {
      state.apply(FuzzAction(kind: .setValue, target: target, value: "English"))
      #expect(state.mode == .languages && state.popover == .closed)
    }
    state.apply(FuzzAction(kind: .press, target: "Language use specimen button"))
    #expect(state.mode == .text)
    state.apply(FuzzAction(kind: .shortcut, keyCode: 20, modifiers: 1 << 20))
    state.apply(FuzzAction(kind: .press, target: "Inspect language U+0041"))
    #expect(state.mode == .glyph)
    state.apply(FuzzAction(kind: .shortcut, keyCode: 20, modifiers: 1 << 20))
    state.apply(FuzzAction(kind: .press, target: "Language missing base disclosure"))
    #expect(state.mode == .languages)
    state.apply(
      FuzzAction(kind: .press, target: "Language missing eng/0/Latn/primary base 41 false 0"))
    #expect(state.mode == .glyph)
  }

  @Test func languageInputsExploreNamesAndSpeakerUnits() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 100)
    for target in [
      "Language search field", "Search languages", "Language query", "Language speaker field",
      "Minimum speaker count", "Minimum language speakers",
    ] {
      var values: Set<String> = []
      for _ in 0..<128 {
        let action = explorer.next(
          from: [FuzzAction(kind: .setValue, target: target)], using: &random)
        values.insert(action.value!)
      }
      if target.contains("search") || target == "Search languages" || target == "Language query" {
        #expect(values.contains("eng") && values.contains("Ancient Greek"))
      } else {
        #expect(values.contains("All") && values.contains("8.3M") && values.contains("100K"))
      }
    }
  }
}
