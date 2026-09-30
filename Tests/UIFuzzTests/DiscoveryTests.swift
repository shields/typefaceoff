import CoreGraphics
import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct DiscoveryTests {
  let world = FakeWorld()

  static let sheetFrame = CGRect(x: 200, y: 150, width: 600, height: 400)
  static let insideSheet = CGRect(x: 220, y: 170, width: 100, height: 30)
  static let panelFrame = CGRect(x: 100, y: 100, width: 300, height: 300)
  static let insidePanel = CGRect(x: 120, y: 120, width: 100, height: 30)
  static let menuFrame = CGRect(x: 300, y: 0, width: 200, height: 300)
  static let insideMenu = CGRect(x: 310, y: 10, width: 180, height: 20)
  static let barItemFrame = CGRect(x: 100, y: 0, width: 40, height: 20)

  func button(_ name: String, at frame: CGRect = FakeWorld.controlFrame) -> FakeNode {
    world.node("AXButton", name: name, frame: frame)
  }

  func workbench() -> FakeNode {
    world.node("AXGroup", frame: nil, children: [button("Font A Size"), button("Font B Size")])
  }

  func sheet(hidden: Bool? = nil, enabled: Bool? = nil) -> FakeNode {
    world.node(
      "AXSheet", name: "Match sheet", frame: Self.sheetFrame, enabled: enabled, hidden: hidden,
      children: [
        button("Apply", at: Self.insideSheet), button("Cancel", at: Self.insideSheet),
      ])
  }

  func panel(role: String, subrole: String = "", children: [FakeNode]) -> FakeNode {
    world.node(
      role, subrole: subrole, name: "Panel", frame: Self.panelFrame,
      children: children + [button("Panel button", at: Self.insidePanel)])
  }

  /// A closed menu has no frame, so the visibility rules prune it.
  func menuBar(open: String? = nil) -> FakeNode {
    world.node(
      "AXMenuBar", frame: nil,
      children: ["Edit", "View", "Window"].map { title in
        world.node(
          "AXMenuBarItem", attributes: AccessibilityAttributes(title: title),
          frame: Self.barItemFrame,
          children: [
            world.node(
              "AXMenu", name: "\(title) menu", frame: title == open ? Self.menuFrame : nil,
              children: [world.node("AXMenuItem", name: "\(title) item", frame: Self.insideMenu)])
          ])
      })
  }

  func discover(_ application: FakeNode, focused: FakeNode?) -> DiscoveryCapture<FakeNode> {
    Discovery.capture(application: application, focusedWindow: { focused?.identity })
  }

  func names(_ capture: DiscoveryCapture<FakeNode>) -> [String] {
    capture.elements.map { $0.node.fakeAttributes.discoveryTarget ?? "<\($0.role)>" }
  }

  struct Scenario: CustomStringConvertible {
    var name: String
    var application: FakeNode
    var focused: FakeNode?
    var source: WindowScopeSource
    var focus: FocusLocation?
    var root: [Int]?
    var rootRole: String?
    var unlocated = false
    var offered: [String]
    var description: String { name }
  }

  static let sheetControls = ["Match sheet", "Apply", "Cancel"]
  static let everything = [
    "Workbench", "Font A Size", "Font B Size", "Panel", "Panel button", "Edit", "View",
  ]

  func scenarios() -> [Scenario] {
    var result: [Scenario] = []

    let nested = sheet()
    result.append(
      Scenario(
        name: "a sheet nested in the window has focus",
        application: world.application([
          world.window(name: "Workbench", children: [workbench(), nested]), menuBar(),
        ]), focused: nested, source: .overlay, focus: .scopeWindow, root: [0, 1],
        rootRole: "AXSheet", offered: Self.sheetControls))

    let beside = sheet()
    result.append(
      Scenario(
        name: "a sheet listed beside the window has focus",
        application: world.application([
          world.window(name: "Workbench", children: [workbench()]), beside, menuBar(),
        ]), focused: beside, source: .overlay, focus: .applicationChild, root: [1],
        rootRole: "AXSheet", offered: Self.sheetControls))

    let floating = panel(role: "AXWindow", subrole: "AXFloatingWindow", children: [])
    result.append(
      Scenario(
        name: "a focused top-level window of another kind is the modal too",
        application: world.application([
          world.window(name: "Workbench", children: [workbench()]), floating, menuBar(),
        ]), focused: floating, source: .overlay, focus: .applicationChild, root: [1],
        rootRole: "AXWindow", offered: ["Panel", "Panel button"]))

    let popover = world.node(
      "AXPopover", name: "Font picker", frame: Self.panelFrame,
      children: [button("Search installed fonts", at: Self.insidePanel)])
    result.append(
      Scenario(
        name: "a popover nested in the window has focus",
        application: world.application([
          world.window(name: "Workbench", children: [workbench(), popover]), menuBar(),
        ]), focused: popover, source: .overlay, focus: .scopeWindow, root: [0, 1],
        rootRole: "AXPopover", offered: ["Font picker", "Search installed fonts"]))

    let underMenu = sheet()
    result.append(
      Scenario(
        name: "an open menu is deeper than the focused sheet and wins",
        application: world.application([
          world.window(name: "Workbench", children: [workbench(), underMenu]),
          menuBar(open: "View"),
        ]), focused: underMenu, source: .overlay, focus: .scopeWindow, root: [1, 1, 0],
        rootRole: "AXMenu", offered: ["View menu", "View item"]))

    let deep = sheet()
    result.append(
      Scenario(
        name: "a focused sheet as deep as an open menu that comes first keeps the tie",
        application: world.application([
          menuBar(open: "View"),
          world.window(
            name: "Workbench",
            children: [world.node("AXGroup", frame: nil, children: [button("Font A Size"), deep])]),
        ]), focused: deep, source: .overlay, focus: .scopeWindow, root: [1, 0, 1],
        rootRole: "AXSheet", offered: Self.sheetControls))

    let front = sheet()
    result.append(
      Scenario(
        name: "a sheet on the front-most of two standard windows",
        application: world.application([
          world.window(name: "Workbench", children: [workbench(), front]),
          world.window(name: "Second", children: [button("Other window")]), menuBar(),
        ]), focused: front, source: .overlay, focus: .scopeWindow, root: [0, 1],
        rootRole: "AXSheet", offered: Self.sheetControls))

    let inFloating = sheet()
    result.append(
      Scenario(
        name: "a sheet inside a top-level floating window is located there",
        application: world.application([
          world.window(name: "Workbench", children: [workbench()]),
          world.node(
            "AXWindow", subrole: "AXFloatingWindow", frame: FakeWorld.windowFrame,
            children: [inFloating]), menuBar(),
        ]), focused: inFloating, source: .overlay, focus: .otherChild, root: [1, 0],
        rootRole: "AXSheet", offered: Self.sheetControls))

    let disabled = sheet(enabled: false)
    result.append(
      Scenario(
        name: "a focused sheet that is not offered itself is still the modal",
        application: world.application([
          world.window(name: "Workbench", children: [workbench(), disabled]), menuBar(),
        ]), focused: disabled, source: .overlay, focus: .scopeWindow, root: [0, 1],
        rootRole: "AXSheet", offered: ["Apply", "Cancel"]))

    let hidden = sheet(hidden: true)
    result.append(
      Scenario(
        name: "a hidden focused sheet is not found, so nothing is offered",
        application: world.application([
          world.window(name: "Workbench", children: [workbench(), hidden]), menuBar(),
        ]), focused: hidden, source: .overlay, focus: .notFound, root: nil, rootRole: nil,
        unlocated: true, offered: []))

    let window = world.window(name: "Workbench", children: [workbench()])
    let unfocused = panel(role: "AXWindow", subrole: "AXFloatingWindow", children: [])
    let plain = world.application([window, unfocused, menuBar()])
    result.append(
      Scenario(
        name: "an unfocused overlay that is not a sheet, popover, or menu narrows nothing",
        application: plain, focused: window, source: .focused, focus: .standardWindow,
        root: nil, rootRole: nil, offered: Self.everything))
    result.append(
      Scenario(
        name: "no focus offers everything",
        application: plain, focused: nil, source: .frontmost, focus: nil, root: nil,
        rootRole: nil, offered: Self.everything))
    result.append(
      Scenario(
        name: "a focus that is not in the tree and no modal by role offers nothing",
        application: plain, focused: world.node("AXSheet"), source: .overlay,
        focus: .notFound, root: nil, rootRole: nil, unlocated: true, offered: []))

    let byRole = sheet()
    result.append(
      Scenario(
        name: "a sheet is found by role when the focus is not in the tree",
        application: world.application([
          world.window(name: "Workbench", children: [workbench(), byRole]), menuBar(),
        ]), focused: world.node("AXSheet"), source: .overlay, focus: .notFound, root: [0, 1],
        rootRole: "AXSheet", offered: Self.sheetControls))

    let unfocusedSheet = sheet()
    let scopeWindow = world.window(name: "Workbench", children: [workbench(), unfocusedSheet])
    result.append(
      Scenario(
        name: "a sheet that does not hold focus is found by role",
        application: world.application([scopeWindow, menuBar()]), focused: scopeWindow,
        source: .focused, focus: .standardWindow, root: [0, 1], rootRole: "AXSheet",
        offered: Self.sheetControls))

    let openMenuWindow = world.window(name: "Workbench", children: [workbench()])
    result.append(
      Scenario(
        name: "an open menu is found by role while the window has focus",
        application: world.application([openMenuWindow, menuBar(open: "Edit")]),
        focused: openMenuWindow, source: .focused, focus: .standardWindow, root: [1, 0, 0],
        rootRole: "AXMenu", offered: ["Edit menu", "Edit item"]))

    let disabledBehind = sheet(enabled: false)
    let disabledWindow = world.window(name: "Workbench", children: [workbench(), disabledBehind])
    result.append(
      Scenario(
        name: "an unfocused sheet that is not offered itself is not the modal",
        application: world.application([disabledWindow, menuBar()]), focused: disabledWindow,
        source: .focused, focus: .standardWindow, root: nil, rootRole: nil,
        offered: [
          "Workbench", "Font A Size", "Font B Size", "Apply", "Cancel", "Edit", "View",
        ]))

    let disabledUnknown = world.window(
      name: "Workbench", children: [workbench(), sheet(enabled: false)])
    result.append(
      Scenario(
        name: "an unlocated focus is not rescued by a sheet that is not offered itself",
        application: world.application([disabledUnknown, menuBar()]),
        focused: world.node("AXSheet"), source: .overlay, focus: .notFound, root: nil,
        rootRole: nil, unlocated: true, offered: []))

    let buried = world.node(
      "AXGroup", frame: nil, hidden: true, children: [sheet()])
    let prunedWindow = world.window(name: "Workbench", children: [workbench(), buried])
    result.append(
      Scenario(
        name: "a sheet inside a pruned subtree is never walked and narrows nothing",
        application: world.application([prunedWindow, menuBar()]), focused: prunedWindow,
        source: .focused, focus: .standardWindow, root: nil, rootRole: nil,
        offered: ["Workbench", "Font A Size", "Font B Size", "Edit", "View"]))

    let holder = world.node("AXGroup", frame: nil, children: [button("Buried")])
    let holderWindow = world.window(
      name: "Workbench",
      children: [world.node("AXGroup", frame: nil, hidden: true, children: [holder]), sheet()])
    result.append(
      Scenario(
        name: "a focus holder inside a pruned subtree is not found, and the sheet by role wins",
        application: world.application([holderWindow, menuBar()]), focused: holder,
        source: .overlay, focus: .notFound, root: [0, 1], rootRole: "AXSheet",
        offered: Self.sheetControls))

    return result
  }

  @Test func discoveryOffersOnlyWhatTheModalRootHolds() throws {
    for scenario in scenarios() {
      let capture = discover(scenario.application, focused: scenario.focused)
      #expect(capture.scope.source == scenario.source, "\(scenario)")
      #expect(capture.modal.focus == scenario.focus, "\(scenario)")
      #expect(capture.modal.root == scenario.root, "\(scenario)")
      #expect(capture.modal.rootRole == scenario.rootRole, "\(scenario)")
      #expect(capture.unlocated == scenario.unlocated, "\(scenario)")
      #expect(names(capture) == scenario.offered, "\(scenario)")
      #expect(
        capture.offersShortcuts == (scenario.root == nil && !scenario.unlocated), "\(scenario)")
    }
  }

  @Test func anUnlocatedOverlayLeavesOnlyPlainKeysIncludingEscape() {
    let hidden = sheet(hidden: true)
    let application = world.application([
      world.window(name: "Workbench", children: [workbench(), hidden]), menuBar(),
    ])
    let capture = discover(application, focused: hidden)
    #expect(capture.unlocated)
    #expect(capture.elements.isEmpty)
    #expect(!capture.offersShortcuts)
    let keys = ActionExplorer.keyboardActions(includeShortcuts: capture.offersShortcuts)
    #expect(keys.allSatisfy { $0.kind == .key })
    #expect(keys.contains { $0.keyCode == 53 })
  }

  @Test func treeDumpsOfferExactlyWhatDiscoveryOffers() {
    for scenario in scenarios() {
      let discovered = discover(scenario.application, focused: scenario.focused).elements.map(
        \.path)
      let dump = TreeDump.capture(
        TreeDumpTests.Fixture().context, application: scenario.application,
        focusedWindow: { scenario.focused?.identity }, clock: FakeClock())
      #expect(dump.entries.filter(\.offered).map(\.path) == discovered, "\(scenario)")
    }
  }

  @Test func everyOfferedControlResolvesByItsPath() {
    for scenario in scenarios() {
      for element in discover(scenario.application, focused: scenario.focused).elements {
        let request = ResolutionRequest(
          FuzzAction(
            kind: .press, target: element.node.fakeAttributes.discoveryTarget,
            targetPath: element.path, targetRole: element.role), allowVisibleTieBreak: false)
        let resolution = world.resolver(scenario.application, focused: scenario.focused).resolve(
          request)
        #expect(resolution.node === element.node, "\(scenario): \(request.label)")
        #expect(resolution.step == .path, "\(scenario): \(request.label)")
      }
    }
  }

  @Test func aSheetIsIdentifiedByTheControlsOnlyItHas() {
    let cases: [([String], FuzzAction.Sheet?)] = [
      (["Cancel matching", "Cancel", "Apply"], .match),
      (["xmark.circle.fill", "Cancel", "Apply"], .match),
      (["Custom specimen text", "Cancel", "Apply"], .editor),
      (["Cancel", "Apply"], nil),
    ]
    for (names, expected) in cases {
      let sheet = world.node(
        "AXSheet", name: "Sheet", frame: Self.sheetFrame,
        children: names.map { button($0, at: Self.insideSheet) })
      let application = world.application([
        world.window(name: "Workbench", children: [workbench(), sheet]), menuBar(),
      ])
      let capture = discover(application, focused: sheet)
      #expect(
        FuzzAction.Sheet.identify(
          rootRole: capture.modal.rootRole,
          targets: capture.elements.map { $0.node.fakeAttributes.discoveryTarget })
          == expected, "\(names)")
    }
  }

  @Test func onlyASheetOverlayIsTaggedWithASheet() {
    let popover = world.node(
      "AXPopover", name: "Popover", frame: Self.panelFrame,
      children: [button("Cancel matching", at: Self.insidePanel)])
    let application = world.application([
      world.window(name: "Workbench", children: [workbench(), popover]), menuBar(),
    ])
    let capture = discover(application, focused: popover)
    #expect(capture.modal.rootRole == "AXPopover")
    let targets = capture.elements.map { $0.node.fakeAttributes.discoveryTarget }
    #expect(targets.contains("Cancel matching"))
    #expect(FuzzAction.Sheet.identify(rootRole: capture.modal.rootRole, targets: targets) == nil)

    let window = world.window(
      name: "Workbench", children: [workbench(), button("Custom specimen text")])
    let plain = discover(world.application([window, menuBar()]), focused: window)
    #expect(plain.modal.rootRole == nil)
    #expect(
      FuzzAction.Sheet.identify(
        rootRole: plain.modal.rootRole,
        targets: plain.elements.map { $0.node.fakeAttributes.discoveryTarget }) == nil)
    #expect(FuzzAction.Sheet.identify(rootRole: "AXSheet", targets: [nil, "Apply"]) == nil)
  }

  @Test func escapeStaysAvailableWhenShortcutsAreWithheld() {
    let keys = ActionExplorer.keyboardActions(includeShortcuts: false)
    #expect(keys.contains { $0.kind == .key && $0.keyCode == 53 })
    #expect(keys.allSatisfy { $0.kind == .key })
  }

  @Test func onlyTheFrontMostStandardWindowIsWalked() {
    let behind = button("Behind")
    let front = sheet()
    let second = world.window(name: "Second", children: [behind])
    let application = world.application([
      world.window(name: "Workbench", children: [workbench(), front]), second, menuBar(),
    ])
    let capture = discover(application, focused: front)
    #expect(capture.scope.scopeIndex == 0)
    #expect(capture.scope.standardWindowCount == 2)
    #expect(world.reads(of: behind, "visibility") == 0)
    #expect(world.reads(of: second, "children") == 0)
  }

  @Test func theFocusedWindowIsReadOnce() {
    let front = sheet()
    let application = world.application([
      world.window(name: "Workbench", children: [workbench(), front]), menuBar(),
    ])
    var reads = 0
    _ = Discovery.capture(
      application: application,
      focusedWindow: {
        reads += 1
        return front.identity
      })
    #expect(reads == 1)
  }

  @Test func hiddenDisabledClippedAndChromeControlsAreNotOffered() {
    let window = world.window(
      name: "Workbench",
      children: [
        world.node("AXButton", subrole: "AXCloseButton", name: "Close"),
        world.node("AXButton", name: "Hidden", hidden: true),
        world.node("AXButton", name: "Disabled", enabled: false),
        world.node(
          "AXButton", name: "Clipped", frame: CGRect(x: 2000, y: 2000, width: 100, height: 30)),
        button("Visible"),
      ])
    let application = world.application([window, menuBar()])
    #expect(
      names(discover(application, focused: window)) == ["Workbench", "Visible", "Edit", "View"])
  }

  @Test func aNodeReachedTwiceIsOfferedOnce() {
    let shared = button("Twice")
    let window = world.window(name: "Workbench", children: [shared, shared])
    let application = world.application([window])
    #expect(names(discover(application, focused: window)) == ["Workbench", "Twice"])
  }

  @Test func theNodeLimitStopsTheWalk() {
    let window = world.window(
      name: "Workbench", children: ["One", "Two", "Three", "Four"].map { button($0) })
    let application = world.application([window])
    #expect(
      names(
        Discovery.capture(
          application: application, focusedWindow: { window.identity }, nodeLimit: 3))
        == ["Workbench", "One", "Two"])
    #expect(
      names(discover(application, focused: window))
        == ["Workbench", "One", "Two", "Three", "Four"])
  }
}
