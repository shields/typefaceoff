import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct MutationStateTests {
  private static let command = UInt64(1 << 20)
  private static let shift = UInt64(1 << 17)
  private static let option = UInt64(1 << 19)

  private static func shortcut(_ keyCode: UInt16, _ modifiers: UInt64 = command) -> FuzzAction {
    FuzzAction(kind: .shortcut, keyCode: keyCode, modifiers: modifiers)
  }

  private static func press(_ target: String) -> FuzzAction {
    FuzzAction(kind: .press, target: target)
  }

  private static func set(_ target: String, commit: Bool? = nil) -> FuzzAction {
    FuzzAction(kind: .setValue, target: target, value: "x", commitValue: commit)
  }

  private static func key(_ keyCode: UInt16) -> FuzzAction {
    FuzzAction(kind: .key, keyCode: keyCode)
  }

  private static let openEditor = shortcut(14, command | shift)
  private static let openMatch = shortcut(46, command | shift)
  private static let glyphMode = shortcut(19)
  private static let textMode = shortcut(18)
  private static let findCharacter = shortcut(3)
  private static let escape = key(53)
  private static let canvasPress = press("Glyph canvas")
  private static let zoomIn = press("Zoom in")
  private static let editorText = set("Custom specimen text")
  private static let fontSearch = set("Search installed fonts")
  private static let characterSearch = set("Search Unicode characters")

  private static func describe(_ action: FuzzAction) -> String {
    let detail = action.target ?? action.keyCode.map { String($0) } ?? ""
    let modifiers = action.modifiers.map { "/\($0)" } ?? ""
    return "\(action.kind.rawValue) \(detail)\(modifiers)"
  }

  private static func repaired(
    _ actions: [FuzzAction], maximumActions: Int = 512
  ) -> [FuzzAction] {
    TraceMutator(maximumActions: maximumActions).repaired(actions)
  }

  private static func expected(_ actions: [FuzzAction]) -> [String] { actions.map(describe) }

  @Test(
    arguments: [
      ([canvasPress], [glyphMode, canvasPress]),
      ([press("Search characters")], [glyphMode, press("Search characters")]),
      ([editorText], [openEditor, editorText]),
      ([press("Apply")], [openEditor, press("Apply")]),
      ([press("Tracking")], [openMatch, press("Tracking")]),
      ([fontSearch], [press("Font A family"), fontSearch]),
      ([characterSearch], [findCharacter, characterSearch]),
      (
        [openEditor, zoomIn],
        [openEditor, escape, glyphMode, zoomIn]
      ),
      (
        [press("Font A family"), editorText],
        [press("Font A family"), escape, openEditor, editorText]
      ),
      (
        [press("Font A family"), characterSearch],
        [press("Font A family"), escape, findCharacter, characterSearch]
      ),
      (
        [openEditor, press("Tracking")],
        [openEditor, escape, openMatch, press("Tracking")]
      ),
      (
        [openEditor, press("Cancel"), press("Apply")],
        [openEditor, press("Cancel"), openEditor, press("Apply")]
      ),
      (
        [press("Font A family"), fontSearch, fontSearch],
        [press("Font A family"), fontSearch, escape, press("Font A family"), fontSearch]
      ),
      (
        [press("Font A family"), press("Font A family"), fontSearch],
        [press("Font A family"), press("Font A family"), fontSearch]
      ),
      (
        [press("Font A family"), FuzzAction(kind: .click, target: "Font A family"), fontSearch],
        [
          press("Font A family"), FuzzAction(kind: .click, target: "Font A family"), escape,
          press("Font A family"), fontSearch,
        ]
      ),
      (
        [press("Search characters"), press("Font A family"), fontSearch],
        [
          glyphMode, press("Search characters"), press("Font A family"), escape,
          press("Font A family"), fontSearch,
        ]
      ),
      (
        [characterSearch, press("Font A family"), fontSearch],
        [
          findCharacter, characterSearch, press("Font A family"), escape, press("Font A family"),
          fontSearch,
        ]
      ),
      (
        [glyphMode, press("Font B specimen")],
        [glyphMode, textMode, press("Font B specimen")]
      ),
      (
        [
          FuzzAction(kind: .click, target: "Font A specimen"),
          FuzzAction(kind: .scroll, target: "Font B specimen"),
        ],
        [
          FuzzAction(kind: .click, target: "Font A specimen"), textMode,
          FuzzAction(kind: .scroll, target: "Font B specimen"),
        ]
      ),
      (
        [glyphMode, canvasPress, zoomIn],
        [glyphMode, canvasPress, glyphMode, zoomIn]
      ),
      (
        [glyphMode, FuzzAction(kind: .click, target: "Glyph canvas"), zoomIn],
        [glyphMode, FuzzAction(kind: .click, target: "Glyph canvas"), glyphMode, zoomIn]
      ),
      (
        [openEditor, key(36), editorText],
        [openEditor, key(36), openEditor, editorText]
      ),
      (
        [press("Font A family"), fontSearch, openEditor, escape, editorText],
        [press("Font A family"), fontSearch, openEditor, escape, escape, openEditor, editorText]
      ),
      (
        [press("Match…"), key(36), press("Tracking")],
        [press("Match…"), key(36), press("Tracking")]
      ),
      (
        [press("Edit text"), press("Match…"), press("Tracking")],
        [press("Edit text"), press("Match…"), escape, openMatch, press("Tracking")]
      ),
      (
        [openEditor, glyphMode, zoomIn],
        [openEditor, glyphMode, escape, glyphMode, zoomIn]
      ),
      (
        [press("Inspect U+0041 LATIN CAPITAL LETTER A"), zoomIn],
        [press("Inspect U+0041 LATIN CAPITAL LETTER A"), zoomIn]
      ),
      (
        [press("Glyph"), zoomIn, press("Text"), press("Font A specimen")],
        [press("Glyph"), zoomIn, press("Text"), press("Font A specimen")]
      ),
      (
        [findCharacter, characterSearch, set("Search Unicode characters", commit: false)],
        [
          findCharacter, characterSearch, escape, findCharacter,
          set("Search Unicode characters", commit: false),
        ]
      ),
      (
        [findCharacter, textMode, characterSearch],
        [findCharacter, textMode, findCharacter, characterSearch]
      ),
      (
        [press("Search characters"), canvasPress, characterSearch],
        [glyphMode, press("Search characters"), canvasPress, findCharacter, characterSearch]
      ),
      (
        [findCharacter, FuzzAction(kind: .click, target: "Glyph canvas"), characterSearch],
        [
          findCharacter, FuzzAction(kind: .click, target: "Glyph canvas"), escape, findCharacter,
          characterSearch,
        ]
      ),
      (
        [shortcut(45), zoomIn],
        [shortcut(45), escape, escape, glyphMode, zoomIn]
      ),
      (
        [shortcut(45), textMode, press("Font A specimen")],
        [shortcut(45), textMode, escape, escape, textMode, press("Font A specimen")]
      ),
      (
        [FuzzAction(kind: .selectFont, target: "Font A family", value: "Menlo"), press("Zoom in")],
        [FuzzAction(kind: .selectFont, target: "Font A family", value: "Menlo"), glyphMode, zoomIn]
      ),
    ] as [([FuzzAction], [FuzzAction])])
  func enablersPrecedeStateDependentControls(plan: [FuzzAction], expected: [FuzzAction]) {
    #expect(Self.repaired(plan).map(Self.describe) == Self.expected(expected))
  }

  @Test func repairedStepsKeepTheirDelaysAndSettleBeforeShortcuts() {
    let repaired = Self.repaired([
      FuzzAction(kind: .press, target: "Font A family"), Self.editorText,
    ])
    #expect(repaired.map(\.delayMilliseconds) == [30, 400, 400, 30])
    #expect(Self.repaired([Self.canvasPress]).map(\.delayMilliseconds) == [50, 30])
  }

  @Test func lockLabelFollowsTheLockState() {
    let lock = FuzzAction(
      kind: .press, target: "Lock appearance", targetPath: [1, 2], targetRole: "AXButton")
    let flipped = Self.repaired([lock])
    #expect(flipped == [FuzzAction(kind: .press, target: "Unlock appearance")])
    let unlock = FuzzAction(
      kind: .press, target: "Unlock appearance", targetPath: [1, 2], targetRole: "AXButton")
    #expect(Self.repaired([unlock]) == [unlock])
    #expect(
      Self.repaired([Self.press("Unlock appearance"), Self.press("Unlock appearance")])
        .compactMap(\.target) == ["Unlock appearance", "Lock appearance"])
    #expect(
      Self.repaired([Self.press("Unlock appearance"), Self.press("Lock appearance")])
        .compactMap(\.target) == ["Unlock appearance", "Lock appearance"])
    // Undo restores an earlier lock state, so the label is no longer predictable.
    for undo in [
      Self.shortcut(6), Self.shortcut(6, Self.command | Self.shift), Self.press("Undo"),
      Self.press("arrow.uturn.backward"),
    ] {
      #expect(Self.repaired([undo, lock]) == [undo, lock])
    }
    #expect(
      Self.repaired([Self.shortcut(6, Self.option), lock]).last?.target == "Unlock appearance")
  }

  @Test func repairedStepsKeepTheirOtherFieldsAndUnrelatedStepsAreUntouched() {
    let drag = FuzzAction(
      kind: .drag, target: "Glyph canvas", deltaX: 3, deltaY: -4, delayMilliseconds: 7)
    #expect(Self.repaired([drag]).last == drag)
    let plain = [
      Self.press("Swap fonts"), Self.key(124), FuzzAction(kind: .pause),
      FuzzAction(kind: .press, targetPath: [1, 2], targetRole: "AXButton"),
      FuzzAction(kind: .increment, target: "Font A Size"),
      FuzzAction(kind: .showMenu, targetPath: [0, 1], targetRole: "AXToolbar"),
      FuzzAction(kind: .scroll, target: "Font A specimen", deltaX: 1, deltaY: 2),
      Self.shortcut(19, Self.command | Self.shift), Self.shortcut(18, Self.command | Self.option),
    ]
    #expect(Self.repaired(plain) == plain)
  }

  @Test func stepsThatDoNotFitTheirEnablersBecomePauses() {
    let pause = FuzzAction(kind: .pause, delayMilliseconds: 1)
    let enabler = FuzzAction(
      kind: .shortcut, keyCode: 19, modifiers: Self.command, delayMilliseconds: 50)
    #expect(Self.repaired([Self.canvasPress], maximumActions: 2) == [enabler, Self.canvasPress])
    #expect(Self.repaired([Self.canvasPress], maximumActions: 1) == [pause])
    #expect(
      Self.repaired(Array(repeating: Self.canvasPress, count: 4), maximumActions: 4)
        == Array(repeating: pause, count: 4))
    // Later steps still need room after earlier steps take theirs.
    #expect(
      Self.repaired([Self.canvasPress, Self.press("Swap fonts")], maximumActions: 2)
        == [pause, Self.press("Swap fonts")])
  }

  @Test func enablersEstablishTheirRequirementFromEveryState() {
    let modes: [WorkbenchState.Mode?] = [nil, .text, .glyph]
    let sheets: [WorkbenchState.Sheet?] = [nil, .closed, .editor, .match]
    let popovers: [WorkbenchState.Popover?] = [nil, .closed, .fonts, .characters]
    let requirements: [WorkbenchState.Requirement] = [
      .mode(.text), .mode(.glyph), .sheet(.editor), .sheet(.match), .sheet(nil),
      .popover(.fonts), .popover(.characters),
    ]
    for mode in modes {
      for sheet in sheets {
        for popover in popovers {
          for requirement in requirements {
            var state = WorkbenchState(
              mode: mode, sheet: sheet, popover: popover, appearanceLocked: nil)
            let actions = state.enable(requirement)
            #expect(state.satisfies(requirement))
            #expect((1...4).contains(actions.count))
          }
        }
      }
    }
  }

  @Test func plansFromMutationNeverTargetAControlThatCannotExist() {
    let mutator = TraceMutator(maximumTextUnits: 32, installedFontFamilies: ["A", "B"])
    let corpus = mutator.initialCorpus(seed: 5)
    var checked = 0
    for seed in 0..<1500 {
      let base = corpus[seed % corpus.count]
      var trace = mutator.mutate(base, seed: UInt64(seed))
      if seed.isMultiple(of: 3) { trace = mutator.mutate(trace, seed: UInt64(seed) &+ 99) }
      #expect(mutator.repaired(trace.actions) == trace.actions)
      var state = WorkbenchState.launch
      for action in trace.actions {
        if let requirement = WorkbenchState.requirement(of: action) {
          #expect(state.satisfies(requirement))
          checked += 1
        }
        if let locked = state.appearanceLocked {
          #expect(
            action.target != (locked ? "Lock appearance" : "Unlock appearance"))
        }
        state.apply(action)
      }
    }
    #expect(checked > 500)
  }

  @Test func handWrittenSeedsAlreadyEstablishTheirRequirements() {
    let mutator = TraceMutator(installedFontFamilies: ["A", "B"])
    for seed in mutator.initialCorpus(seed: 9) {
      #expect(mutator.repaired(seed.actions) == seed.actions)
    }
  }

  @Test func mutationNeverReturnsItsInput() {
    let mutator = TraceMutator(maximumTextUnits: 32, installedFontFamilies: ["A"])
    let tight = TraceMutator(maximumActions: 4, maximumTextUnits: 32)
    var cases: [(TraceMutator, FuzzTrace)] = mutator.initialCorpus(seed: 3).map { (mutator, $0) }
    cases.append((tight, FuzzTrace(seed: 0, actions: [Self.press("Swap fonts")])))
    cases.append((tight, FuzzTrace(seed: 0, actions: [FuzzAction(kind: .pause)])))
    cases.append(
      (tight, FuzzTrace(seed: 0, actions: Array(repeating: Self.press("Swap fonts"), count: 4))))
    for (subject, base) in cases {
      let input = subject.constrained(base).actions
      for seed in 0..<600 {
        #expect(subject.mutate(base, seed: UInt64(seed)).actions != input)
      }
    }
  }

  @Test func mutationShortcutsMatchTheExplorerAndNeverCloseOrQuit() {
    let mutator = TraceMutator(maximumTextUnits: 32, installedFontFamilies: ["A"])
    let drawn = Set(
      (0..<4000).flatMap { mutator.mutate(FuzzTrace(seed: 0), seed: UInt64($0)).actions }
        .filter { $0.kind == .shortcut }
        .map { Shortcut(keyCode: $0.keyCode!, modifiers: $0.modifiers!) })
    let explored = Set(
      ActionExplorer.keyboardActions(includeShortcuts: true)
        .filter { $0.kind == .shortcut }
        .map { Shortcut(keyCode: $0.keyCode!, modifiers: $0.modifiers!) })
    #expect(drawn == explored)
    let closing = [12, 13, 4].map { UInt16($0) }
    #expect(drawn.allSatisfy { !closing.contains($0.keyCode) })
    #expect(drawn.allSatisfy { $0.keyCode != 46 || $0.modifiers & Self.shift != 0 })
  }

  private struct Shortcut: Hashable {
    var keyCode: UInt16
    var modifiers: UInt64
  }
}
