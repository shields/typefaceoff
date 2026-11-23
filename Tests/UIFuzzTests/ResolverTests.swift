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

import CoreGraphics
import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct ResolverTests {
  let world = FakeWorld()

  func request(
    _ target: String?, path: [Int]? = nil, role: String? = "AXButton", tieBreak: Bool = false
  ) -> ResolutionRequest {
    ResolutionRequest(
      FuzzAction(kind: .press, target: target, targetPath: path, targetRole: role),
      allowVisibleTieBreak: tieBreak)
  }

  func expectFound(
    _ resolution: Resolution<FakeNode>, _ node: FakeNode, _ step: ResolutionStep,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(resolution.node === node, sourceLocation: sourceLocation)
    #expect(resolution.step == step, sourceLocation: sourceLocation)
  }

  func expectMissing(
    _ resolution: Resolution<FakeNode>, _ miss: ResolutionMiss,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    guard case .missing(let actual) = resolution else {
      Issue.record("Expected missing, got \(resolution)", sourceLocation: sourceLocation)
      return
    }
    #expect(actual == miss, sourceLocation: sourceLocation)
  }

  func expectAmbiguous(
    _ resolution: Resolution<FakeNode>, matches: Int, offered: Int,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    guard case .ambiguous(let actualMatches, let actualOffered) = resolution else {
      Issue.record("Expected ambiguous, got \(resolution)", sourceLocation: sourceLocation)
      return
    }
    #expect(actualMatches == matches, sourceLocation: sourceLocation)
    #expect(actualOffered == offered, sourceLocation: sourceLocation)
  }

  struct Workbench {
    var size: FakeNode
    var field: FakeNode
    var reset: FakeNode
    var group: FakeNode
    var window: FakeNode
    var menuBar: FakeNode
    var application: FakeNode
  }

  func workbench(inserting extra: [FakeNode] = []) -> Workbench {
    let size = world.node("AXButton", name: "Size")
    let field = world.node("AXTextField")
    let reset = world.node("AXButton", name: "Reset")
    let group = world.node("AXGroup", children: extra + [size, field, reset])
    let window = world.window(children: [group])
    let menuBar = world.menuBar(["Edit", "View"])
    return Workbench(
      size: size, field: field, reset: reset, group: group, window: window, menuBar: menuBar,
      application: world.application([window, menuBar]))
  }

  @Test func aPathHitReturnsTheRecordedNodeWithoutAnyFilter() {
    let bench = workbench()
    let resolver = world.resolver(bench.application, focused: bench.window)
    expectFound(
      resolver.resolve(request("Size", path: [0, 0, 0])), bench.size, .path)
    bench.size.isHidden = true
    bench.size.isEnabled = false
    bench.size.frame = nil
    expectFound(
      world.resolver(bench.application, focused: bench.window).resolve(
        request("Size", path: [0, 0, 0])), bench.size, .path)
  }

  @Test func theMatchSeedResolvesButtonsAlongsideStaticOptionLabels() throws {
    let open = world.node("AXButton", name: "Match…")
    let label = world.node("AXStaticText", name: "Tracking")
    let optimize = world.node(
      "AXButton",
      attributes: AccessibilityAttributes(
        identifier: "Font B Optimize tracking", description: "Optimize Tracking"))
    let cancel = world.node("AXButton", name: "Cancel")
    let window = world.window(children: [open, label, optimize, cancel])
    let app = world.application([window])
    let seed = try #require(
      TraceMutator().initialCorpus(seed: 1).first { $0.actions.first?.target == "Match…" })
    #expect(seed.actions.count == 3)
    for (action, button) in zip(seed.actions, [open, optimize, cancel]) {
      let request = ResolutionRequest(action, allowVisibleTieBreak: false)
      expectFound(world.resolver(app, focused: window).resolve(request), button, .firstName)
    }
  }

  @Test func aRoleMismatchIsNotAPathHit() {
    let bench = workbench()
    let resolver = world.resolver(bench.application, focused: bench.window)
    expectMissing(resolver.resolve(request("Size", path: [0, 0, 0], role: "AXSlider")), .noMatch)
  }

  @Test func aNameMismatchFallsBackToTheUniqueNameElsewhere() {
    let bench = workbench()
    let resolver = world.resolver(bench.application, focused: bench.window)
    expectFound(
      resolver.resolve(request("Reset", path: [0, 0, 0])), bench.reset, .uniqueName)
  }

  @Test func aTargetMatchesAnyOfTheFourNames() {
    let help = world.node("AXButton", attributes: AccessibilityAttributes(help: "Hint"))
    let window = world.window(children: [help])
    let app = world.application([window])
    expectFound(
      world.resolver(app, focused: window).resolve(request("Hint", path: [0, 0])), help, .path)
  }

  @Test func theRoleIsComparedAsRecordedIncludingTheEmptyRole() {
    let bare = world.node("", name: "Odd")
    let window = world.window(children: [bare])
    let app = world.application([window])
    expectFound(
      world.resolver(app, focused: window).resolve(request("Odd", path: [0, 0], role: "")), bare,
      .path)
    expectMissing(
      world.resolver(app, focused: window).resolve(request("Odd", path: [0, 0], role: nil)),
      .noMatch)
    expectFound(
      world.resolver(app, focused: window).resolve(ResolutionRequest(target: "Odd")), bare,
      .firstName)
  }

  @Test func anUnnamedPathHitsButAStaleOneIsMissing() {
    let bench = workbench()
    let hit = request(nil, path: [0, 0, 1], role: "AXTextField")
    expectFound(
      world.resolver(bench.application, focused: bench.window).resolve(hit), bench.field, .path)

    let progress = world.node("AXProgressIndicator")
    let shifted = workbench(inserting: [progress])
    expectMissing(
      world.resolver(shifted.application, focused: shifted.window).resolve(hit), .noMatch)
  }

  @Test func aShiftedPathIsRescuedByAUniqueName() {
    let progress = world.node("AXProgressIndicator")
    let bench = workbench(inserting: [progress])
    let resolver = world.resolver(bench.application, focused: bench.window)
    expectFound(resolver.resolve(request("Size", path: [0, 0, 0])), bench.size, .uniqueName)
  }

  @Test func outOfRangeEmptyAndBrokenPathsAreMissingWithoutAName() {
    let bench = workbench()
    for path in [[], [9, 0], [0, 7], [0, 0, 9], [0, 0, 0, 0]] {
      let resolver = world.resolver(bench.application, focused: bench.window)
      expectMissing(
        resolver.resolve(request(nil, path: path, role: "AXButton")), .noMatch)
    }
  }

  @Test func aNamedRequestWithABrokenPathStillFindsItsUniqueName() {
    let bench = workbench()
    for path in [[], [9, 0], [0, 7]] {
      expectFound(
        world.resolver(bench.application, focused: bench.window).resolve(
          request("Size", path: path)), bench.size, .uniqueName)
    }
  }

  struct TwoWindows {
    var first: FakeNode
    var second: FakeNode
    var firstSize: FakeNode
    var secondSize: FakeNode
    var onlyInFirst: FakeNode
    var menuBar: FakeNode
    var application: FakeNode
  }

  func twoWindows() -> TwoWindows {
    let firstSize = world.node("AXButton", name: "Font B Size")
    let secondSize = world.node("AXButton", name: "Font B Size")
    let onlyInFirst = world.node("AXButton", name: "Zed")
    let first = world.window(children: [world.node("AXGroup", children: [firstSize, onlyInFirst])])
    let second = world.window(children: [world.node("AXGroup", children: [secondSize])])
    let menuBar = world.menuBar(["Edit"])
    return TwoWindows(
      first: first, second: second, firstSize: firstSize, secondSize: secondSize,
      onlyInFirst: onlyInFirst, menuBar: menuBar,
      application: world.application([first, second, menuBar]))
  }

  @Test func aPathIntoAnotherWindowIsOutsideTheScope() {
    let windows = twoWindows()
    let named = request("Font B Size", path: [0, 0, 0], role: "AXButton")
    let resolver = world.resolver(windows.application, focused: windows.second)
    expectFound(resolver.resolve(named), windows.secondSize, .uniqueName)
    expectMissing(
      world.resolver(windows.application, focused: windows.second).resolve(
        request(nil, path: [0, 0, 0])), .pathOutsideScope)
    expectMissing(
      world.resolver(windows.application, focused: windows.second).resolve(
        request("Zed", path: [0, 0, 1])), .pathOutsideScope)
  }

  @Test func onlyTheFocusedWindowIsCounted() {
    let windows = twoWindows()
    let unrelated = windows.firstSize
    let resolver = world.resolver(windows.application, focused: windows.second)
    expectFound(
      resolver.resolve(request("Font B Size", path: [1, 0, 0])), windows.secondSize, .path)
    expectFound(
      world.resolver(windows.application, focused: windows.second).resolve(
        request("Font B Size", path: [9])), windows.secondSize, .uniqueName)
    #expect(world.reads(of: unrelated, "role") == 0)
    #expect(world.reads(of: unrelated, "attributes") == 0)
    expectFound(
      world.resolver(windows.application, focused: windows.first).resolve(
        request("Font B Size", path: [9])), windows.firstSize, .uniqueName)
  }

  @Test func withoutFocusTheFrontMostWindowIsTheScope() {
    let windows = twoWindows()
    expectFound(
      world.resolver(windows.application, focused: nil).resolve(
        request("Font B Size", path: [9])), windows.firstSize, .uniqueName)
    expectFound(
      world.resolver(windows.application, focused: nil).resolve(
        request("Font B Size", path: [0, 0, 0])), windows.firstSize, .path)
    expectMissing(
      world.resolver(windows.application, focused: nil).resolve(request(nil, path: [1, 0, 0])),
      .pathOutsideScope)
  }

  @Test func aFocusedOverlayKeepsTheFrontMostWindowInResolutionScope() {
    let popover = world.node("AXWindow", subrole: "AXFloatingWindow", children: [])
    let windows = twoWindows()
    let application = world.application(windows.application.childNodes + [popover])
    expectFound(
      world.resolver(application, focused: popover).resolve(request("Font B Size", path: [9])),
      windows.firstSize, .uniqueName)
    #expect(
      world.resolver(application, focused: popover).scope.source == .overlay)
  }

  @Test func aMenuBarPathShiftedByAnotherWindowIsRescuedByName() {
    let windows = twoWindows()
    let menuItem = windows.menuBar.childNodes[0].childNodes[0].childNodes[0]
    let stale = request("Edit item", path: [1, 0, 0, 0], role: "AXMenuItem")
    expectFound(
      world.resolver(windows.application, focused: windows.first).resolve(stale), menuItem,
      .uniqueName)
    expectFound(
      world.resolver(windows.application, focused: windows.second).resolve(stale), menuItem,
      .uniqueName)
    let current = request("Edit item", path: [2, 0, 0, 0], role: "AXMenuItem")
    expectFound(
      world.resolver(windows.application, focused: windows.first).resolve(current), menuItem,
      .path)
  }

  @Test func theScopeIsComputedOnlyWhenTheCheapPathStepCannotDecide() {
    let windows = twoWindows()
    let hit = world.resolver(windows.application, focused: windows.second)
    expectFound(hit.resolve(request("Font B Size", path: [1, 0, 0])), windows.secondSize, .path)
    #expect(world.focusReads == 1)
    #expect(world.reads(of: windows.first, "role") == 0)
    #expect(world.reads(of: windows.menuBar, "role") == 0)

    let menu = world.resolver(windows.application, focused: windows.second)
    expectFound(
      menu.resolve(request("Edit item", path: [2, 0, 0, 0], role: "AXMenuItem")),
      windows.menuBar.childNodes[0].childNodes[0].childNodes[0], .path)
    #expect(world.focusReads == 1)

    let outside = world.resolver(windows.application, focused: windows.second)
    expectFound(
      outside.resolve(request("Font B Size", path: [0, 0, 0])), windows.secondSize, .uniqueName)
    #expect(world.focusReads == 2)
    #expect(world.reads(of: windows.first, "role") >= 1)
  }

  struct Inspectors {
    var resetA: FakeNode
    var resetB: FakeNode
    var groupA: FakeNode
    var groupB: FakeNode
    var unrelated: FakeNode
    var sibling: FakeNode
    var window: FakeNode
    var application: FakeNode
  }

  func inspectors(
    groupBRole: String = "AXGroup", bFrame: CGRect? = FakeWorld.controlFrame
  ) -> Inspectors {
    let resetA = world.node("AXButton", name: "Reset size")
    let resetB = world.node("AXButton", name: "Reset size", frame: bFrame)
    let groupA = world.node("AXGroup", children: [resetA])
    let groupB = world.node(
      groupBRole,
      frame: groupBRole == "AXScrollArea" ? CGRect(x: 0, y: 0, width: 50, height: 50) : nil,
      children: [resetB])
    let unrelated = world.node("AXButton", name: "Other")
    let sibling = world.node("AXGroup", children: [unrelated])
    let window = world.window(children: [groupA, groupB, sibling])
    return Inspectors(
      resetA: resetA, resetB: resetB, groupA: groupA, groupB: groupB, unrelated: unrelated,
      sibling: sibling, window: window, application: world.application([window]))
  }

  func resolveStale(_ scene: Inspectors, tieBreak: Bool) -> Resolution<FakeNode> {
    world.resolver(scene.application, focused: scene.window).resolve(
      request("Reset size", path: [0, 9, 9], tieBreak: tieBreak))
  }

  @Test func sameNamedControlsThatAreAllOfferedStayAmbiguous() {
    let scene = inspectors()
    expectAmbiguous(resolveStale(scene, tieBreak: true), matches: 2, offered: 2)
    expectAmbiguous(resolveStale(scene, tieBreak: false), matches: 2, offered: 2)
  }

  @Test func theSingleVisibleTwinIsChosenOnlyForLivePicks() {
    let scene = inspectors()
    scene.resetB.isHidden = true
    expectFound(resolveStale(scene, tieBreak: true), scene.resetA, .visibleName)
    expectAmbiguous(resolveStale(scene, tieBreak: false), matches: 2, offered: 1)
  }

  @Test func noVisibleTwinIsAmbiguousEvenForLivePicks() {
    let scene = inspectors()
    scene.resetA.isEnabled = false
    scene.resetB.isHidden = true
    expectAmbiguous(resolveStale(scene, tieBreak: true), matches: 2, offered: 0)
  }

  @Test func aHiddenAncestorExcludesACandidate() {
    let scene = inspectors()
    scene.groupB.isHidden = true
    expectFound(resolveStale(scene, tieBreak: true), scene.resetA, .visibleName)
  }

  @Test func aClippedCandidateIsNotOffered() {
    let scene = inspectors(groupBRole: "AXScrollArea")
    expectFound(resolveStale(scene, tieBreak: true), scene.resetA, .visibleName)
  }

  @Test func aCandidateWithoutAFrameIsNotOffered() {
    let scene = inspectors(bFrame: nil)
    expectFound(resolveStale(scene, tieBreak: true), scene.resetA, .visibleName)
  }

  @Test func aPrunedAncestorChainExcludesACandidateEvenWhenItLooksVisible() {
    let scene = inspectors()
    let chrome = world.node("AXGroup", subrole: "AXCloseButton", children: [scene.resetB])
    scene.groupB.childNodes = [chrome]
    expectFound(resolveStale(scene, tieBreak: true), scene.resetA, .visibleName)
  }

  struct Menus {
    var system: FakeNode
    var submenuItem: FakeNode
    var own: FakeNode
    var window: FakeNode
    var application: FakeNode
  }

  func menus() -> Menus {
    let system = world.menuItem("_performStandardShareMenuItem:", title: "Open")
    let submenuItem = world.menuItem("rewrite", title: "Open")
    let writingTools = world.menuItem(
      "__NSTextViewContextSubmenuIdentifierWritingTools", title: "Writing Tools",
      children: [world.node("AXMenu", frame: FakeWorld.windowFrame, children: [submenuItem])])
    let own = world.menuItem("open", title: "Open")
    let menu = world.node(
      "AXMenu", frame: FakeWorld.windowFrame, children: [system, writingTools, own])
    let window = world.window(children: [menu])
    return Menus(
      system: system, submenuItem: submenuItem, own: own, window: window,
      application: world.application([window]))
  }

  @Test func menuItemsThatOpenSystemUIAreNotVisibleTwins() {
    let scene = menus()
    let stale = request("Open", path: [0, 9], role: "AXMenuItem", tieBreak: true)
    expectFound(
      world.resolver(scene.application, focused: scene.window).resolve(stale), scene.own,
      .visibleName)
    expectAmbiguous(
      world.resolver(scene.application, focused: scene.window).resolve(
        request("Open", path: [0, 9], role: "AXMenuItem")), matches: 3, offered: 1)
  }

  @Test func aRecordedPathStillReachesAMenuItemThatDiscoveryNoLongerOffers() {
    let scene = menus()
    expectFound(
      world.resolver(scene.application, focused: scene.window).resolve(
        request("_performStandardShareMenuItem:", path: [0, 0, 0], role: "AXMenuItem")),
      scene.system, .path)
    expectFound(
      world.resolver(scene.application, focused: scene.window).resolve(
        request("_performStandardShareMenuItem:", path: [0, 9], role: "AXMenuItem")),
      scene.system, .uniqueName)
    expectFound(
      world.resolver(scene.application, focused: scene.window).resolve(
        request("rewrite", path: [0, 0, 1, 0, 0], role: "AXMenuItem")), scene.submenuItem, .path)
  }

  @Test func theTieBreakReadsOnlyTheCandidatesAncestorChains() {
    let scene = inspectors()
    scene.resetB.isHidden = true
    _ = resolveStale(scene, tieBreak: true)
    for node in [scene.unrelated, scene.sibling] {
      #expect(world.reads(of: node, "visibility") == 0)
    }
    for node in [scene.resetA, scene.resetB, scene.groupA, scene.groupB, scene.window] {
      #expect(world.reads(of: node, "visibility") >= 1)
    }
  }

  @Test func uniqueNamesNeverReadVisibility() {
    let bench = workbench()
    _ = world.resolver(bench.application, focused: bench.window).resolve(
      request("Size", path: [9]))
    #expect(world.reads(of: bench.size, "visibility") == 0)
    #expect(world.reads(of: bench.window, "visibility") == 0)
  }

  @Test func targetOnlyReturnsTheFirstMatchInDocumentOrder() {
    let scene = inspectors()
    let resolver = world.resolver(scene.application, focused: scene.window)
    expectFound(resolver.resolve(ResolutionRequest(target: "Reset size")), scene.resetA, .firstName)
  }

  @Test func targetOnlyFindsHiddenAndClippedNodes() {
    let hidden = world.node("AXTextView", name: "Font A specimen", hidden: true)
    let clipped = world.node(
      "AXTextView", name: "Font B specimen",
      frame: CGRect(x: 4000, y: 4000, width: 900, height: 900))
    let area = world.node(
      "AXScrollArea", frame: CGRect(x: 0, y: 0, width: 50, height: 50), children: [clipped])
    let window = world.window(children: [hidden, area])
    let app = world.application([window])
    expectFound(
      world.resolver(app, focused: window).resolve(ResolutionRequest(target: "Font A specimen")),
      hidden, .firstName)
    expectFound(
      world.resolver(app, focused: window).resolve(ResolutionRequest(target: "Font B specimen")),
      clipped, .firstName)
  }

  @Test func targetOnlySearchesTheScopeOnly() {
    let windows = twoWindows()
    let resolver = world.resolver(windows.application, focused: windows.second)
    expectMissing(resolver.resolve(ResolutionRequest(target: "Zed")), .noMatch)
    expectFound(
      world.resolver(windows.application, focused: windows.first).resolve(
        ResolutionRequest(target: "Zed")), windows.onlyInFirst, .firstName)
  }

  @Test func aRequestWithNeitherTargetNorPathHasNoTarget() {
    let bench = workbench()
    let none = ResolutionRequest(
      FuzzAction(kind: .press), allowVisibleTieBreak: true)
    expectMissing(
      world.resolver(bench.application, focused: bench.window).resolve(none), .noTarget)
    expectMissing(
      world.resolver(bench.application, focused: bench.window).resolve(
        ResolutionRequest(target: "Nowhere")), .noMatch)
  }

  @Test func theNodeLimitStopsTheWalk() {
    let buttons = (0..<4).map { world.node("AXButton", name: "B\($0)") }
    let window = world.window(children: buttons)
    let app = world.application([window])
    // Visit order: window, B0, B1, B2, B3.
    expectMissing(
      world.resolver(app, focused: window, nodeLimit: 4).resolve(ResolutionRequest(target: "B3")),
      .noMatch)
    expectFound(
      world.resolver(app, focused: window, nodeLimit: 5).resolve(ResolutionRequest(target: "B3")),
      buttons[3], .firstName)
    expectMissing(
      world.resolver(app, focused: window, nodeLimit: 4).resolve(request("B3", path: [9])),
      .noMatch)
    expectFound(
      world.resolver(app, focused: window, nodeLimit: 5).resolve(request("B3", path: [9])),
      buttons[3], .uniqueName)
  }

  @Test func anIdentityReachedTwiceIsVisitedOnce() {
    let shared = world.node("AXButton", name: "Size")
    let window = world.window(children: [
      world.node("AXGroup", children: [shared]), world.node("AXGroup", children: [shared]),
    ])
    let app = world.application([window])
    expectFound(
      world.resolver(app, focused: window).resolve(request("Size", path: [9])), shared,
      .uniqueName)
    #expect(world.reads(of: shared, "children") == 1)
  }

  @Test func readErrorsMakeAMissBecomeUnreadable() {
    let bench = workbench()
    bench.group.failsToReadChildren = true
    for path in [[0, 0, 1], [9]] {
      expectMissing(
        world.resolver(bench.application, focused: bench.window).resolve(
          request("Gone", path: path)), .unreadable)
    }
    expectMissing(
      world.resolver(bench.application, focused: bench.window).resolve(
        ResolutionRequest(target: "Gone")), .unreadable)
  }

  @Test func readErrorsMakeAnAmbiguityUnreadableButNeverHideAFind() {
    let scene = inspectors()
    let broken = world.node("AXGroup")
    broken.failsToReadChildren = true
    scene.window.childNodes.append(broken)
    expectMissing(resolveStale(scene, tieBreak: true), .unreadable)
    expectFound(
      world.resolver(scene.application, focused: scene.window).resolve(
        request("Other", path: [9])), scene.unrelated, .uniqueName)
  }

  @Test func aCaptureThatRunsOutOfTimeIsUnreadable() {
    let bench = workbench()
    let clock = FakeClock()
    world.clock = clock
    world.secondsPerRead = 1
    let resolver = world.resolver(
      bench.application, focused: bench.window, clock: clock, budget: 0.5)
    expectMissing(resolver.resolve(ResolutionRequest(target: "Reset")), .unreadable)
    expectMissing(
      world.resolver(bench.application, focused: bench.window, clock: clock, budget: 0.5).resolve(
        request("Reset", path: [9])), .unreadable)
    expectMissing(
      world.resolver(bench.application, focused: bench.window, clock: clock, budget: 3.5).resolve(
        request(nil, path: [0, 0, 1], role: "AXTextField")), .unreadable)
  }

  @Test func aWalkCutShortByTheBudgetNeverVouchesForAUniqueName() {
    let scene = inspectors()
    let clock = FakeClock()
    world.clock = clock
    world.secondsPerRead = 1
    // A twelve-second budget at one second per read ends the walk after Reset A, before its twin.
    let short = world.resolver(
      scene.application, focused: scene.window, clock: clock, budget: 12)
    expectMissing(short.resolve(request("Reset size", path: [0, 9, 9])), .unreadable)
    let generous = world.resolver(
      scene.application, focused: scene.window, clock: clock, budget: 1_000)
    expectAmbiguous(
      generous.resolve(request("Reset size", path: [0, 9, 9])), matches: 2, offered: 2)
  }

  @Test func aLookupThatExcludesTheMenuBarNeverReadsIt() throws {
    let bench = workbench()
    let probe = ResolutionRequest(target: "Reset", excludesMenuBar: true)
    expectFound(
      world.resolver(bench.application, focused: bench.window).resolve(probe), bench.reset,
      .firstName)
    let inMenu = ResolutionRequest(target: "Edit item", excludesMenuBar: true)
    expectMissing(
      world.resolver(bench.application, focused: bench.window).resolve(inMenu), .noMatch)
    #expect(world.reads(of: bench.menuBar, "children") == 0)
    let item = try #require(bench.menuBar.subtree.first { $0.fakeRole == "AXMenuItem" })
    expectFound(
      world.resolver(bench.application, focused: bench.window).resolve(
        ResolutionRequest(target: "Edit item")), item, .firstName)
    #expect(world.reads(of: bench.menuBar, "children") >= 1)
    #expect(!ResolutionRequest(target: "Reset").excludesMenuBar)
  }

  @Test func eachResolveStartsAFreshBudgetAndAGenerousOneHidesNothing() {
    let bench = workbench()
    let clock = FakeClock()
    world.clock = clock
    world.secondsPerRead = 1
    let resolver = world.resolver(
      bench.application, focused: bench.window, clock: clock, budget: 4.5)
    expectMissing(resolver.resolve(ResolutionRequest(target: "Reset")), .unreadable)
    world.secondsPerRead = 0
    expectFound(resolver.resolve(ResolutionRequest(target: "Reset")), bench.reset, .firstName)

    world.secondsPerRead = 1
    let generous = world.resolver(
      bench.application, focused: bench.window, clock: clock, budget: 1_000)
    expectFound(generous.resolve(ResolutionRequest(target: "Reset")), bench.reset, .firstName)
  }

  @Test func requestsDescribeThemselves() {
    let action = FuzzAction(
      kind: .setValue, target: nil, targetPath: [0, 0, 20, 7], targetRole: "AXTextField")
    let unnamed = ResolutionRequest(action, allowVisibleTieBreak: true)
    #expect(unnamed.label == "[0, 0, 20, 7]")
    #expect(unnamed.key == "AXTextField <unnamed>")
    #expect(unnamed.runKey == "AXTextField [0, 0, 20, 7]")
    #expect(unnamed.allowVisibleTieBreak)

    let named = ResolutionRequest(
      FuzzAction(kind: .press, target: "Size", targetPath: [1], targetRole: "AXButton"),
      allowVisibleTieBreak: false)
    #expect(named.label == "Size")
    #expect(named.key == "AXButton Size")
    #expect(named.runKey == "AXButton Size")
    #expect(!named.allowVisibleTieBreak)

    let bare = ResolutionRequest(FuzzAction(kind: .press), allowVisibleTieBreak: false)
    #expect(bare.label == "<missing target>")
    #expect(bare.key == " <unnamed>")
    #expect(bare.runKey == " <unnamed>")

    let roleless = ResolutionRequest(
      FuzzAction(kind: .press, targetPath: [4]), allowVisibleTieBreak: false)
    #expect(roleless.runKey == " [4]")
    #expect(Resolution<FakeNode>.missing(.noMatch).step == nil)
    #expect(Resolution<FakeNode>.ambiguous(matches: 2, offered: 0).node == nil)

    let search = ResolutionRequest(target: "Search installed fonts")
    #expect(search.label == "Search installed fonts")
    #expect(search.path == nil && search.role == nil && !search.allowVisibleTieBreak)
  }

  @Test func failuresCarryTheLegacySignatureAndACountFreeAmbiguousSignature() {
    let path = request(nil, path: [0, 0, 20, 7], role: "AXTextField")
    let bare = ResolutionRequest(FuzzAction(kind: .press), allowVisibleTieBreak: false)
    let named = request("Font B Size", path: [1])
    let found = Resolution<FakeNode>.found(world.node("AXButton"), .path)
    #expect(found.failure(for: named) == nil)

    let cases: [(Resolution<FakeNode>, ResolutionRequest, String)] = [
      (.missing(.noMatch), path, "Control not found: [0, 0, 20, 7]"),
      (.missing(.pathOutsideScope), path, "Control not found: [0, 0, 20, 7]"),
      (.missing(.unreadable), named, "Control not found: Font B Size"),
      (.missing(.noTarget), bare, "Control not found: <missing target>"),
      (.ambiguous(matches: 2, offered: 1), named, "Ambiguous control: Font B Size"),
      (.ambiguous(matches: 5, offered: 0), named, "Ambiguous control: Font B Size"),
    ]
    for (resolution, request, signature) in cases {
      #expect(resolution.failure(for: request)?.description == signature)
    }
    #expect(
      Resolution<FakeNode>.ambiguous(matches: 2, offered: 1).failure(for: named)?.kind
        == .ambiguous(matches: 2, offered: 1))
    #expect(
      Resolution<FakeNode>.missing(.noMatch).failure(for: named)
        == ResolutionFailure.missing("Font B Size"))
  }

  @Test func failureReasonsAndSkippability() {
    let reasons: [(ResolutionFailure.Kind, String, Bool)] = [
      (.missing(.noTarget), "The action names no control", true),
      (.missing(.noMatch), "No control matched in the scope window", true),
      (
        .missing(.pathOutsideScope),
        "The recorded path points into a window that is not the scope window", true
      ),
      (
        .missing(.unreadable), "The accessibility tree could not be read completely in time",
        false
      ),
      (
        .ambiguous(matches: 3, offered: 2), "3 controls have this name and 2 of them are offered",
        true
      ),
    ]
    for (kind, reason, skippable) in reasons {
      let failure = ResolutionFailure(kind: kind, label: "x")
      #expect(failure.reason == reason)
      #expect(failure.isSkippable == skippable)
    }
    #expect(ResolutionSignature.persistent == "Persistent stale control: ")
    #expect(
      ResolutionStep.allCases.map(\.rawValue) == ["path", "uniqueName", "visibleName", "firstName"])
  }

  @Test func attributesAndNamesFollowDiscoveryPrecedence() {
    let all = AccessibilityAttributes(
      identifier: "id", title: "title", description: "description", help: "help")
    #expect(all.names == ["id", "title", "description", "help"])
    #expect(all.discoveryTarget == "id")
    #expect(
      AccessibilityAttributes(title: "title", description: "description").discoveryTarget
        == "title")
    #expect(
      AccessibilityAttributes(description: "description", help: "help").discoveryTarget
        == "description")
    let helpOnly = AccessibilityAttributes(help: "help")
    #expect(helpOnly.discoveryTarget == nil)
    #expect(helpOnly.names == ["help"])
    #expect(AccessibilityAttributes().names.isEmpty)
    #expect(AccessibilityAttributes().discoveryTarget == nil)

    let node = world.node("AXButton", attributes: all)
    #expect(node.names == all.names)
    #expect(node.hasName("help") && node.hasName("id") && !node.hasName("other"))
    #expect(!world.node("AXButton").hasName(""))
  }
}

/// `singleWindowLegacyDifferential` holds only for one standard window, where scope changes
/// nothing; the two-window test states how scoping differs.
@Suite struct LegacyDifferentialTests {
  static let roles = [
    "AXButton", "AXTextField", "AXSlider", "AXGroup", "AXScrollArea", "AXCheckBox",
  ]
  static let names = ["Size", "Tracking", "Reset", "Kerning"]

  struct Generator {
    let world: FakeWorld
    var random: SplitMix64

    mutating func pick(_ count: Int) -> Int { Int(random.next() % UInt64(count)) }

    mutating func attributes() -> AccessibilityAttributes {
      var values = ["", "", "", ""]
      if pick(10) < 6 { values[pick(4)] = LegacyDifferentialTests.names[pick(4)] }
      if pick(10) < 2 { values[pick(4)] = LegacyDifferentialTests.names[pick(4)] }
      return AccessibilityAttributes(
        identifier: values[0], title: values[1], description: values[2], help: values[3])
    }

    mutating func subtree(depth: Int) -> [FakeNode] {
      (0..<pick(depth < 3 ? 5 : 1)).map { _ in
        let role = LegacyDifferentialTests.roles[pick(6)]
        let small = role == "AXScrollArea" && pick(10) < 3
        let hidden = pick(12) == 0 ? true : nil
        let enabled = pick(12) == 0 ? false : nil
        return world.node(
          role, attributes: attributes(),
          frame: small ? CGRect(x: 0, y: 0, width: 50, height: 50) : FakeWorld.controlFrame,
          enabled: enabled, hidden: hidden, children: subtree(depth: depth + 1))
      }
    }
  }

  struct Entry {
    var path: [Int]
    var node: FakeNode
  }

  func entries(_ node: FakeNode, path: [Int] = []) -> [Entry] {
    node.childNodes.enumerated().flatMap { index, child in
      [Entry(path: path + [index], node: child)] + entries(child, path: path + [index])
    }
  }

  func actions(for entry: Entry, random: inout SplitMix64) -> [FuzzAction] {
    let role = entry.node.fakeRole
    let name = entry.node.fakeAttributes.names.sorted().first
    var shifted = entry.path
    shifted[shifted.count - 1] += 1
    let wrongRole = random.next() % 2 == 0 ? "AXCheckBox" : "AXSlider"
    return [
      FuzzAction(kind: .press, target: name, targetPath: entry.path, targetRole: role),
      FuzzAction(kind: .press, target: nil, targetPath: entry.path, targetRole: role),
      FuzzAction(kind: .press, target: name, targetPath: shifted, targetRole: role),
      FuzzAction(kind: .press, target: name, targetRole: role),
      FuzzAction(kind: .press, target: "Nope", targetPath: entry.path, targetRole: role),
      FuzzAction(kind: .press, target: name, targetPath: entry.path, targetRole: wrongRole),
    ]
  }

  @Test func singleWindowLegacyDifferential() {
    var sawTieBreak = false
    var sawAmbiguous = false
    var sawPath = false
    for seed in 0..<300 {
      let world = FakeWorld()
      var generator = Generator(world: world, random: SplitMix64(seed: UInt64(seed)))
      let window = world.window(children: generator.subtree(depth: 0))
      let application = world.application([window, world.menuBar(["Edit", "View"])])
      let legacy = LegacyResolver(application: application)
      let all = entries(application)
      for _ in 0..<12 {
        let entry = all[generator.pick(all.count)]
        for action in actions(for: entry, random: &generator.random) {
          for tieBreak in [false, true] {
            let focused = generator.pick(2) == 0 ? nil : window
            let request = ResolutionRequest(action, allowVisibleTieBreak: tieBreak)
            let resolution = world.resolver(application, focused: focused).resolve(request)
            let expected = legacy.require(action)
            switch resolution {
            case .found(let node, let step):
              if let expected {
                #expect(node === expected, "seed \(seed) \(action)")
                sawPath = sawPath || step == .path
              } else {
                #expect(step == .uniqueName || step == .visibleName, "seed \(seed) \(action)")
                #expect(step != .visibleName || tieBreak, "seed \(seed) \(action)")
                sawTieBreak = sawTieBreak || step == .visibleName
              }
            case .ambiguous:
              #expect(expected == nil, "seed \(seed) \(action)")
              sawAmbiguous = true
            case .missing(let miss):
              #expect(expected == nil, "seed \(seed) \(action)")
              #expect(miss == .noMatch || miss == .noTarget, "seed \(seed) \(action)")
            }
          }
        }
      }
    }
    #expect(sawPath && sawTieBreak && sawAmbiguous)
  }

  @Test func twoWindowScopingOnlyRestrictsWhereAControlIsFound() {
    var outside = 0
    for seed in 0..<200 {
      let world = FakeWorld()
      var generator = Generator(world: world, random: SplitMix64(seed: UInt64(1_000 + seed)))
      let first = world.window(children: generator.subtree(depth: 0))
      let second = world.window(children: generator.subtree(depth: 0))
      let menuBar = world.menuBar(["Edit"])
      let application = world.application([first, second, menuBar])
      let focused: FakeNode? = [nil, first, second][generator.pick(3)]
      let scopeWindow = focused ?? first
      let inScope = Set((scopeWindow.subtree + menuBar.subtree).map(\.identity))
      let all = entries(application)
      for _ in 0..<12 {
        let entry = all[generator.pick(all.count)]
        for action in actions(for: entry, random: &generator.random) {
          let request = ResolutionRequest(action, allowVisibleTieBreak: true)
          let resolution = world.resolver(application, focused: focused).resolve(request)
          if let found = resolution.node {
            #expect(inScope.contains(found.identity), "seed \(seed) \(action)")
          }
          guard action.targetPath == entry.path, action.target == nil,
            action.targetRole == entry.node.fakeRole
          else { continue }
          if inScope.contains(entry.node.identity) {
            #expect(resolution.node === entry.node, "seed \(seed) \(action)")
            #expect(resolution.step == .path, "seed \(seed) \(action)")
          } else {
            outside += 1
            if case .missing(.pathOutsideScope) = resolution {
            } else {
              Issue.record("Expected pathOutsideScope, got \(resolution), seed \(seed)")
            }
          }
        }
      }
    }
    #expect(outside > 0)
  }
}
