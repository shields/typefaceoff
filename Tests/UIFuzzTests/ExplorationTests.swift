import Foundation
import Testing

@testable import UIFuzzSupport

private func control(
  _ kind: FuzzAction.Kind, _ target: String?, _ path: [Int], role: String = "AXButton"
) -> FuzzAction {
  FuzzAction(kind: kind, target: target, targetPath: path, targetRole: role)
}

@Suite struct ExplorationTests {
  private func picks(
    _ count: Int, explorer: inout ActionExplorer, random: inout SplitMix64,
    available: (Int) -> [FuzzAction]
  ) -> [FuzzAction] {
    (0..<count).map { explorer.next(from: available($0), using: &random) }
  }

  @Test func driftingPathsOfOneNamedControlCountAsOneControl() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 1)
    let actions = picks(100, explorer: &explorer, random: &random) {
      [control(.press, "Font B Size", [0, 0, 20, $0]), control(.press, "Reset", [0, 0, 3])]
    }
    #expect(actions.filter { $0.target == "Font B Size" }.count == 50)
    #expect(actions.filter { $0.target == "Reset" }.count == 50)
  }

  @Test func duplicateNamesAndDifferentRolesKeepSeparateCounts() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 2)
    let actions = picks(30, explorer: &explorer, random: &random) {
      [
        control(.press, "Reset typography", [0, $0, 1]),
        control(.press, "Reset typography", [0, $0, 2]),
        control(.press, "Reset typography", [0, $0, 3], role: "AXCheckBox"),
      ]
    }
    #expect(actions.filter { $0.targetPath?.last == 1 }.count == 10)
    #expect(actions.filter { $0.targetPath?.last == 2 }.count == 10)
    #expect(actions.filter { $0.targetRole == "AXCheckBox" }.count == 10)
  }

  @Test func unnamedControlsKeepTheirPathAsIdentity() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 3)
    let fixed = (1...3).map { control(.scroll, nil, [0, $0], role: "AXScrollArea") }
    let actions = picks(12, explorer: &explorer, random: &random) { _ in fixed }
    for path in fixed.map(\.targetPath) {
      #expect(actions.filter { $0.targetPath == path }.count == 4)
    }

    var drifting = ActionExplorer(mutator: TraceMutator())
    let pinned = control(.scroll, nil, [0, 99], role: "AXScrollArea")
    let phantoms = picks(50, explorer: &drifting, random: &random) {
      [pinned, control(.scroll, nil, [0, $0], role: "AXScrollArea")]
    }
    #expect(phantoms.filter { $0.targetPath == [0, 99] }.count <= 1)
  }

  @Test func aPickKeepsTheSheetItWasDiscoveredIn() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 7)
    var tagged = control(.press, "Optical Size", [0, 1, 5], role: "AXCheckBox")
    tagged.sheet = .match
    let actions = picks(4, explorer: &explorer, random: &random) { _ in [tagged] }
    #expect(actions.allSatisfy { $0.sheet == .match && $0.target == "Optical Size" })
    let untagged = picks(1, explorer: &explorer, random: &random) { _ in
      [control(.press, "Swap fonts", [0, 2])]
    }
    #expect(untagged[0].sheet == nil)
  }

  @Test func keyboardActionsKeepSeparateCounts() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 4)
    let keyboard = ActionExplorer.keyboardActions(includeShortcuts: true)
    let actions = picks(28, explorer: &explorer, random: &random) { _ in keyboard }
    let keys = actions.filter { $0.kind == .key }
    #expect(keys.count == 14)
    #expect(Dictionary(grouping: keys, by: \.keyCode).values.allSatisfy { $0.count == 2 })
    let shortcuts = actions.filter { $0.kind == .shortcut }
    #expect(Set(shortcuts.map { "\($0.keyCode!)/\($0.modifiers!)" }).count == 13)
  }

  @Test func excludedControlStaysOutOfTheRunUntilTheNextRun() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 5)
    let broken = control(.press, "Broken", [0, 1])
    let available = [
      broken, control(.press, "Fine", [0, 2]),
      control(.scroll, "Area", [0, 3], role: "AXScrollArea"),
    ]
    explorer.exclude(broken)
    explorer.exclude(broken)
    let during = picks(60, explorer: &explorer, random: &random) { _ in available }
    #expect(!during.contains { $0.target == "Broken" })
    #expect(during.contains { $0.target == "Fine" })
    #expect(during.contains { $0.target == "Area" })

    explorer.beginRun()
    let after = picks(60, explorer: &explorer, random: &random) { _ in available }
    #expect(after.contains { $0.target == "Broken" })
  }

  @Test func exclusionCoversEveryKindAndDuplicateAndIgnoresPathDrift() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 6)
    let kinds: [FuzzAction.Kind] = [.click, .drag, .increment]
    let available = kinds.flatMap { kind in
      [
        control(kind, "Font B Size", [0, 1, 9], role: "AXSlider"),
        control(kind, "Font B Size", [1, 1, 9], role: "AXSlider"),
        control(kind, "Font A Size", [0, 1, 8], role: "AXSlider"),
      ]
    }
    explorer.exclude(control(.click, "Font B Size", [7, 7], role: "AXSlider"))
    let actions = picks(90, explorer: &explorer, random: &random) { _ in available }
    #expect(!actions.contains { $0.target == "Font B Size" })
    #expect(Set(actions.map(\.kind)) == Set(kinds))
  }

  @Test func unnamedExclusionIsPerPathAndRole() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 7)
    let available = [
      control(.scroll, nil, [0, 1], role: "AXScrollArea"),
      control(.scroll, nil, [0, 2], role: "AXScrollArea"),
      control(.scroll, nil, [0, 1], role: "AXGroup"),
    ]
    explorer.exclude(available[0])
    let actions = picks(40, explorer: &explorer, random: &random) { _ in available }
    #expect(!actions.contains { $0.targetPath == [0, 1] && $0.targetRole == "AXScrollArea" })
    #expect(actions.contains { $0.targetPath == [0, 2] })
    #expect(actions.contains { $0.targetRole == "AXGroup" })
  }

  @Test func kindWhoseControlsAreAllExcludedIsSkipped() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 8)
    let area = control(.scroll, "Area", [0, 3], role: "AXScrollArea")
    let available = [control(.press, "A", [0, 1]), control(.press, "B", [0, 2]), area]
    explorer.exclude(area)
    let actions = picks(40, explorer: &explorer, random: &random) { _ in available }
    #expect(actions.allSatisfy { $0.kind == .press })
  }

  @Test func filterIsIgnoredWhenNothingWouldBeLeft() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 9)
    let only = control(.press, "Only", [0, 1])
    explorer.exclude(only)
    #expect(explorer.next(from: [only], using: &random).target == "Only")

    let pair = [only, control(.press, "Other", [0, 2])]
    explorer.exclude(pair[1])
    let actions = picks(10, explorer: &explorer, random: &random) { _ in pair }
    #expect(actions.allSatisfy { $0.kind == .press && $0.target != nil })
    #expect(Set(actions.map(\.target)) == ["Only", "Other"])
    #expect(explorer.next(from: [], using: &random).keyCode == 53)
  }

  @Test func beginRunKeepsVisitCounts() {
    for seed in 0..<20 {
      var explorer = ActionExplorer(mutator: TraceMutator())
      var random = SplitMix64(seed: UInt64(seed))
      let available = [control(.press, "A", [0, 1]), control(.press, "B", [0, 2])]
      let first = explorer.next(from: available, using: &random)
      explorer.beginRun()
      #expect(explorer.next(from: available, using: &random).target != first.target)
    }
  }

  @Test func keyboardActionsCannotBeExcluded() async {
    await #expect(processExitsWith: .failure) {
      var explorer = ActionExplorer(mutator: TraceMutator())
      explorer.exclude(FuzzAction(kind: .key, keyCode: 53))
    }
  }
}
