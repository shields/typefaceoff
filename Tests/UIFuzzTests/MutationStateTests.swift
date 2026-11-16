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
  private static let findCharacter = press("Search characters")
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
      ([press("Font B Optimize tracking")], [openMatch, press("Font B Optimize tracking")]),
      ([fontSearch], [press("Font A family"), fontSearch]),
      ([characterSearch], [glyphMode, findCharacter, characterSearch]),
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
        [press("Font A family"), escape, glyphMode, findCharacter, characterSearch]
      ),
      (
        [openEditor, press("Font B Optimize tracking")],
        [openEditor, escape, openMatch, press("Font B Optimize tracking")]
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
          glyphMode, findCharacter, characterSearch, press("Font A family"), escape,
          press("Font A family"),
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
        [press("Match…"), key(36), press("Font B Optimize tracking")],
        [press("Match…"), key(36), escape, openMatch, press("Font B Optimize tracking")]
      ),
      (
        [press("Edit Text…"), press("Match…"), press("Font B Optimize tracking")],
        [
          press("Edit Text…"), press("Match…"), escape, openMatch,
          press("Font B Optimize tracking"),
        ]
      ),
      (
        [openEditor, glyphMode, zoomIn],
        [openEditor, glyphMode, escape, glyphMode, zoomIn]
      ),
      (
        [openMatch, key(36), zoomIn],
        [openMatch, key(36), escape, glyphMode, zoomIn]
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
          glyphMode, findCharacter, characterSearch, escape, findCharacter,
          set("Search Unicode characters", commit: false),
        ]
      ),
      (
        [findCharacter, textMode, characterSearch],
        [glyphMode, findCharacter, textMode, glyphMode, findCharacter, characterSearch]
      ),
      (
        [press("Search characters"), canvasPress, characterSearch],
        [
          glyphMode, press("Search characters"), canvasPress, escape, glyphMode, findCharacter,
          characterSearch,
        ]
      ),
      (
        [findCharacter, FuzzAction(kind: .click, target: "Glyph canvas"), characterSearch],
        [
          glyphMode, findCharacter, FuzzAction(kind: .click, target: "Glyph canvas"), escape,
          glyphMode, findCharacter,
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

  private static func inContext(
    _ sheet: FuzzAction.Context, _ kind: FuzzAction.Kind = .press, _ target: String? = nil,
    path: [Int]? = nil, role: String? = nil
  ) -> FuzzAction {
    FuzzAction(kind: kind, target: target, targetPath: path, targetRole: role, context: sheet)
  }

  @Test(
    arguments: [
      "Stop", "Cancel matching", "Font B Optimize axes", "Font B Optimize typography",
      "Font B Optimize tracking", "Font B Optimize size", "Font B Optimize axis 2003265652",
      "Font B Optimize feature ot.kern",
    ])
  func matchControlsNeedMatchMode(name: String) {
    let control = Self.press(name)
    #expect(WorkbenchState.requirement(of: control) == .operation(.match))
    #expect(
      Self.repaired([control]).map(Self.describe) == Self.expected([Self.openMatch, control]))
    #expect(
      Self.repaired([Self.openEditor, control]).map(Self.describe)
        == Self.expected([Self.openEditor, Self.escape, Self.openMatch, control]))
    #expect(
      Self.repaired([Self.openMatch, control]).map(Self.describe)
        == Self.expected([Self.openMatch, control]))
  }

  @Test func navigatingDuringMatchKeepsThePreviewActive() {
    let actions = [
      Self.openMatch, Self.glyphMode, Self.zoomIn, Self.textMode,
      Self.press("Font B specimen"), Self.set("Find Character", commit: false),
    ]
    #expect(Self.repaired(actions) == actions)
    var state = WorkbenchState.launch
    for action in actions { state.apply(action) }
    #expect(state.operation == .match && state.mode == .text)
    let zoom = Self.repaired([Self.openMatch, Self.zoomIn])
    #expect(
      zoom.map(Self.describe) == Self.expected([Self.openMatch, Self.glyphMode, Self.zoomIn]))
  }

  @Test func lockedControlsCloseMatchBeforeEditing() {
    for target in [
      "Show Inspector", "Font A family", "Font B Size field", "Search Languages",
      "Open typography inspector", "Link A and B",
    ] {
      let actions = Self.repaired([Self.openMatch, Self.press(target)])
      #expect(actions[1].kind == .key && actions[1].keyCode == 53)
      #expect(actions.last?.target == target)
    }
    var state = WorkbenchState.launch
    state.mode = .languages
    state.apply(Self.openMatch)
    #expect(state.mode == .text && state.operation == .match)
    state.apply(Self.shortcut(20))
    state.apply(Self.press("Languages"))
    #expect(state.mode == .text)
  }

  @Test func axisAndFeatureMenuItemsReopenTheirOwnMenu() {
    for (target, menu, popover) in [
      ("Font B Optimize axis 2003265652", "Font B Optimize axes", WorkbenchState.Popover.matchAxes),
      ("Font B Optimize feature ot.liga", "Font B Optimize typography", .matchTypography),
    ] {
      let item = FuzzAction(kind: .press, target: target, targetRole: "AXMenuItem", context: .match)
      #expect(WorkbenchState.requirement(of: item) == .popover(popover))
      #expect(
        Self.repaired([item]).map(Self.describe)
          == Self.expected([
            Self.openMatch, Self.press(menu), item,
          ]))
      #expect(
        Self.repaired([Self.openMatch, Self.press(menu), item, item]).map(Self.describe)
          == Self.expected([
            Self.openMatch, Self.press(menu), item, Self.press(menu), item,
          ]))
      let show = FuzzAction(kind: .showMenu, target: menu)
      #expect(Self.repaired([Self.openMatch, show, item]) == [Self.openMatch, show, item])
      var state = WorkbenchState(operation: .match, fontBPresent: nil)
      _ = state.enable(.popover(popover))
      #expect(state.satisfies(.popover(popover)))
      state.apply(item)
      #expect(state.popover == .closed && state.operation == .match)
      state.fontBPresent = false
      _ = state.enable(.popover(popover))
      #expect(state.satisfies(.popover(popover)))
    }
    #expect(
      WorkbenchState.requirement(of: Self.press("Font B Optimize axis 2003265652"))
        == .operation(.match))
    #expect(
      WorkbenchState.requirement(
        of: FuzzAction(kind: .press, target: "Copy", targetRole: "AXMenuItem")) == nil)
  }

  @Test(
    arguments: [
      press("Cancel"), press("Apply"), press("Cancel matching"), press("Cancel matching"),
      FuzzAction(kind: .click, target: "Cancel matching"), escape,
    ])
  func everyCloserEndsMatchMode(closer: FuzzAction) {
    let size = Self.press("Font B Optimize size")
    #expect(
      Self.repaired([Self.openMatch, closer, size]).map(Self.describe)
        == Self.expected([Self.openMatch, closer, Self.openMatch, size]))
  }

  @Test func aRecordedMenuItemThatOpensSystemUIBecomesAPause() {
    let writingTools = FuzzAction(
      kind: .press, target: "__NSTextViewContextSubmenuIdentifierWritingTools",
      targetRole: "AXMenuItem")
    let search = FuzzAction(
      kind: .press, target: "_searchWithGoogleFromMenu:", targetRole: "AXMenuItem")
    let service = FuzzAction(kind: .press, target: "_processRequest:", targetRole: "AXMenuItem")
    let services = FuzzAction(kind: .press, target: "Services", targetRole: "AXMenuItem")
    let speech = FuzzAction(kind: .click, target: "Start Speaking", targetRole: "AXMenuItem")
    let copy = FuzzAction(kind: .press, target: "_NS:23", targetRole: "AXMenuItem")
    let button = FuzzAction(kind: .press, target: "Summarize", targetRole: "AXButton")
    let repaired = Self.repaired([
      writingTools, search, service, services, copy, speech, button, Self.key(36),
    ])
    #expect(
      repaired.map(\.kind) == [
        .pause, .pause, .pause, .pause, .press, .pause, .press, .key,
      ])
    #expect(repaired[4] == copy)
    #expect(repaired[6] == button)
    #expect(
      Self.repaired([writingTools, writingTools], maximumActions: 2).map(\.kind) == [
        .pause, .pause,
      ])
  }

  @Test func returnMayLeaveMatchActiveSoItsNextControlRequiresReopening() {
    let size = Self.press("Font B Optimize size")
    #expect(
      Self.repaired([Self.openMatch, Self.key(36), size]).map(Self.describe)
        == Self.expected([Self.openMatch, Self.key(36), Self.escape, Self.openMatch, size]))
  }

  @Test(arguments: [press("Cancel"), press("Apply"), escape, key(36)])
  func everyCloserEndsTheEditorSheet(closer: FuzzAction) {
    #expect(
      Self.repaired([Self.openEditor, closer, Self.editorText]).map(Self.describe)
        == Self.expected([Self.openEditor, closer, Self.openEditor, Self.editorText]))
  }

  @Test func aTagNamesTheOperationWhateverTheControlIsCalled() {
    let axis = Self.inContext(.match, .press, "Optical Size")
    let feature = Self.inContext(.match, .press, "Standard Ligatures")
    let unnamed = Self.inContext(
      .match, .scroll, path: [0, 1, 4], role: "AXScrollArea")
    let text = Self.inContext(.editor, .setValue, "Anything")
    for control in [axis, feature, unnamed] {
      #expect(WorkbenchState.requirement(of: control) == .operation(.match))
      let repaired = Self.repaired([control])
      #expect(repaired.map(Self.describe) == Self.expected([Self.openMatch, control]))
      #expect(repaired.last == control)
      #expect(
        Self.repaired([Self.openEditor, control]).map(Self.describe)
          == Self.expected([Self.openEditor, Self.escape, Self.openMatch, control]))
      #expect(
        Self.repaired([Self.openMatch, control]).map(Self.describe)
          == Self.expected([Self.openMatch, control]))
      #expect(
        Self.repaired([Self.openMatch, Self.press("Cancel"), control]).map(Self.describe)
          == Self.expected([Self.openMatch, Self.press("Cancel"), Self.openMatch, control]))
    }
    #expect(WorkbenchState.requirement(of: text) == .operation(.editor))
    #expect(
      Self.repaired([Self.openMatch, text]).map(Self.describe)
        == Self.expected([Self.openMatch, Self.escape, Self.openEditor, text]))
  }

  @Test func aTagOutranksTheNameTable() {
    let editorTracking = Self.inContext(.editor, .press, "Font B Optimize tracking")
    #expect(WorkbenchState.requirement(of: editorTracking) == .operation(.editor))
    let matchApply = Self.inContext(.match, .press, "Apply")
    #expect(WorkbenchState.requirement(of: matchApply) == .operation(.match))
    #expect(WorkbenchState.requirement(of: Self.press("Apply")) == .operation(nil))
    #expect(
      Self.repaired([Self.openEditor, matchApply]).map(Self.describe)
        == Self.expected([Self.openEditor, Self.escape, Self.openMatch, matchApply]))
    #expect(
      Self.repaired([Self.openMatch, editorTracking]).map(Self.describe)
        == Self.expected([Self.openMatch, Self.escape, Self.openEditor, editorTracking]))
  }

  @Test func closersRequireTheOperationTheyCloseWhenTagged() {
    let close = Self.inContext(.match, .press, "Cancel matching")
    let size = Self.inContext(.match, .press, "Some axis")
    #expect(
      Self.repaired([close, size]).map(Self.describe)
        == Self.expected([Self.openMatch, close, Self.openMatch, size]))
  }

  @Test func editingCommandsWaitUntilTheCurrentOperationCloses() {
    let match = Self.press("Match fonts…")
    let edit = Self.press("Edit Sample Text…")
    #expect(
      Self.repaired([match, Self.press("Font B Optimize size")]).map(Self.describe)
        == Self.expected([match, Self.press("Font B Optimize size")]))
    #expect(
      Self.repaired([edit, Self.editorText]).map(Self.describe)
        == Self.expected([edit, Self.editorText]))
    #expect(
      Self.repaired([Self.openEditor, match, Self.press("Font B Optimize size")]).map(Self.describe)
        == Self.expected(
          [Self.openEditor, match, Self.escape, Self.openMatch, Self.press("Font B Optimize size")])
    )
    #expect(
      Self.repaired([Self.openMatch, edit, Self.editorText]).map(Self.describe)
        == Self.expected([Self.openMatch, edit, Self.escape, Self.openEditor, Self.editorText]))
  }

  @Test func editingShortcutsDoNothingDuringAnotherOperation() {
    #expect(
      Self.repaired([Self.openMatch, Self.openMatch, Self.press("Font B Optimize size")]).map(
        Self.describe)
        == Self.expected([Self.openMatch, Self.openMatch, Self.press("Font B Optimize size")]))
    #expect(
      Self.repaired([Self.openMatch, Self.openEditor, Self.editorText]).map(Self.describe)
        == Self.expected(
          [Self.openMatch, Self.openEditor, Self.escape, Self.openEditor, Self.editorText]))
    #expect(
      Self.repaired([Self.openEditor, Self.openMatch, Self.press("Font B Optimize size")]).map(
        Self.describe)
        == Self.expected(
          [
            Self.openEditor, Self.openMatch, Self.escape, Self.openMatch,
            Self.press("Font B Optimize size"),
          ]))
  }

  @Test func repairedStepsKeepTheirDelaysAndSettleBeforeShortcuts() {
    let repaired = Self.repaired([
      FuzzAction(kind: .press, target: "Font A family"), Self.editorText,
    ])
    #expect(repaired.map(\.delayMilliseconds) == [30, 400, 400, 30])
    #expect(Self.repaired([Self.canvasPress]).map(\.delayMilliseconds) == [50, 30])
  }

  @Test func theLinkToggleHasAStableNameAcrossEditsAndUndo() {
    let toggle = FuzzAction(
      kind: .press, target: "Link A and B", targetPath: [1, 2], targetRole: "AXCheckBox")
    let actions = [toggle, toggle, Self.shortcut(6), toggle]
    #expect(Self.repaired(actions) == actions)
  }

  @Test func repairedStepsKeepTheirOtherFieldsAndUnrelatedStepsAreUntouched() {
    let drag = FuzzAction(
      kind: .drag, target: "Glyph canvas", deltaX: 3, deltaY: -4, delayMilliseconds: 7)
    #expect(Self.repaired([drag]).last == drag)
    let plain = [
      Self.press("Swap fonts"), Self.key(124), FuzzAction(kind: .pause),
      FuzzAction(kind: .press, targetPath: [1, 2], targetRole: "AXButton"),
      FuzzAction(kind: .increment, target: "Font A Size field stepper"),
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
    let sheets: [WorkbenchState.Operation?] = [nil, .closed, .editor, .match]
    let popovers: [WorkbenchState.Popover?] = [nil, .closed, .fonts, .characters, .glyphCharacters]
    let requirements: [WorkbenchState.Requirement] = [
      .mode(.text), .mode(.glyph), .operation(.editor), .operation(.match), .operation(nil),
      .popover(.fonts), .popover(.glyphCharacters), .popover(.characters),
    ]
    for mode in modes {
      for sheet in sheets {
        for popover in popovers {
          for requirement in requirements {
            var state = WorkbenchState(
              mode: mode, operation: sheet, popover: popover)
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
        state.apply(action)
      }
    }
    #expect(checked > 500)
  }

  private struct Exploration {
    var actions: [FuzzAction]
    var needs: [FuzzAction: FuzzAction.Context]

    init(_ steps: [(FuzzAction, FuzzAction.Context?)]) {
      actions = steps.map(\.0)
      needs = [:]
      for case (let action, let sheet?) in steps { needs[action] = sheet }
    }
  }

  private static func plain(_ actions: [FuzzAction]) -> [(FuzzAction, FuzzAction.Context?)] {
    actions.map { ($0, nil) }
  }

  private static let workbenchPrefix = plain([
    FuzzAction(kind: .setValue, target: "Font A Size field", value: "44"),
    FuzzAction(kind: .increment, target: "Font A Size"),
    FuzzAction(kind: .increment, target: "Font B Tracking"),
    glyphMode, zoomIn, key(124), textMode, press("Swap fonts"),
    press("Show Inspector"), press("Show Inspector"), key(124), press("Shape"),
  ])

  private static let workbenchSuffix = plain([
    FuzzAction(kind: .scroll, target: "Font A specimen", deltaX: 0, deltaY: 20),
    press("Spacing"), FuzzAction(kind: .increment, target: "Font A Tracking"),
    FuzzAction(kind: .decrement, target: "Font B Size"), glyphMode, press("Reset glyph zoom"),
    textMode, press("Link A and B"), key(123),
    FuzzAction(kind: .setValue, target: "Font A Size field", value: "22"),
    press("Swap fonts"), press("Link A and B"),
  ])

  private static let axisToggle = inContext(.match, .press, "Optical Size")
  private static let featureToggle = inContext(.match, .press, "Standard Ligatures")
  private static let matchList = inContext(
    .match, .scroll, path: [0, 1, 4, 2], role: "AXScrollArea")
  private static let closeMatch = inContext(.match, .press, "Cancel matching")
  private static let applyMatch = inContext(.match, .press, "Apply")
  private static let cancelMatch = inContext(.match, .press, "Cancel")
  private static let editorList = inContext(
    .editor, .scroll, path: [0, 1, 0], role: "AXScrollArea")
  private static let editorField = inContext(.editor, .setValue, "Custom specimen text")
  private static let applyEditor = inContext(.editor, .press, "Apply")

  private static let explorations: [Exploration] = [
    Exploration(
      workbenchPrefix + [
        (openMatch, nil), (press("Font B Optimize size"), .match),
        (press("Font B Optimize feature ot.kern"), .match),
        (press("Font B Optimize leading"), .match), (press("Stop"), .match), (axisToggle, .match),
        (featureToggle, .match), (matchList, .match), (escape, nil),
      ] + workbenchSuffix),
    Exploration(
      workbenchPrefix + [
        (press("Match…"), nil), (axisToggle, .match), (closeMatch, .match),
        (press("Match…"), nil), (featureToggle, .match), (applyMatch, .match), (openMatch, nil),
        (matchList, .match), (press("Font B Optimize leading"), .match), (key(36), nil),
      ] + workbenchSuffix),
    Exploration(
      workbenchPrefix + [
        (openEditor, nil), (editorField, .editor), (editorList, .editor), (applyEditor, .editor),
        (press("Edit Text…"), nil), (editorField, .editor), (escape, nil),
      ] + workbenchSuffix),
    Exploration(
      workbenchPrefix + [
        (press("Comparison"), nil), (press("Match fonts…"), nil), (axisToggle, .match),
        (escape, nil), (press("Comparison"), nil), (press("Edit Sample Text…"), nil),
        (editorField, .editor), (key(36), nil), (press("Match…"), nil), (featureToggle, .match),
        (cancelMatch, .match),
      ] + workbenchSuffix),
  ]

  @Test func explorationsKeepControlsInsideTheirRequiredOperation() {
    let mutator = TraceMutator(maximumTextUnits: 32, installedFontFamilies: ["A", "B"])
    var checked = 0
    var violations: [String] = []
    for (index, exploration) in Self.explorations.enumerated() {
      var remaining = exploration.actions[...]
      for action in mutator.repaired(exploration.actions) where action == remaining.first {
        remaining.removeFirst()
      }
      #expect(remaining.isEmpty)
      for seed in 0..<3000 {
        let trace = mutator.mutate(
          FuzzTrace(seed: 0, actions: exploration.actions), seed: UInt64(index * 10_000 + seed))
        var state = WorkbenchState.launch
        for action in trace.actions {
          if let sheet = exploration.needs[action] {
            checked += 1
            if state.operation != (sheet == .match ? .match : .editor) {
              violations.append("scenario \(index) seed \(seed): \(Self.describe(action))")
            }
          }
          if let requirement = WorkbenchState.requirement(of: action), !state.satisfies(requirement)
          {
            violations.append("scenario \(index) seed \(seed): \(Self.describe(action))")
          }
          state.apply(action)
        }
        if mutator.repaired(trace.actions) != trace.actions {
          violations.append("scenario \(index) seed \(seed) is not stable under repair")
        }
      }
    }
    #expect(violations.isEmpty, "\(violations.prefix(5))")
    #expect(checked > 60_000)
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
