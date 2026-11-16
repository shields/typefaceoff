import CoreGraphics
import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct TreeDumpTests {
  typealias Lines = TelemetryLines

  struct Fixture {
    let world = FakeWorld()
    let clock = FakeClock()
    var app: FakeNode
    var window: FakeNode
    var other: FakeNode

    init() {
      let world = world
      let visible = world.node("AXButton", name: "Visible")
      let hidden = world.node("AXButton", name: "Hidden", hidden: true)
      let disabled = world.node("AXButton", name: "Disabled", enabled: false)
      let clipped = world.node(
        "AXButton", name: "Clipped", frame: CGRect(x: 2000, y: 2000, width: 100, height: 30))
      window = world.window(name: "Typeface/Off", children: [visible, hidden, disabled, clipped])
      other = world.window(children: [world.node("AXButton", name: "Other")])
      let menuBar = world.node(
        "AXMenuBar", frame: nil,
        children: [
          world.node(
            "AXMenuBarItem", attributes: AccessibilityAttributes(title: "Edit"), frame: nil),
          world.node(
            "AXMenuBarItem", attributes: AccessibilityAttributes(title: "Window"), frame: nil,
            children: [world.node("AXMenuItem", name: "Minimize")]),
        ])
      app = world.application([window, other, menuBar])
      clock.advance(10)
    }

    var context: TreeDump.Context {
      let request = ResolutionRequest(
        FuzzAction(kind: .setValue, targetPath: [0, 0, 20, 12], targetRole: "AXTextField"),
        allowVisibleTieBreak: true)
      return TreeDump.Context(
        action: 12, request: request, kind: .setValue,
        error: "Control not found: [0, 0, 20, 12]", attempts: 3, elapsedMilliseconds: 514,
        telemetry: TelemetrySummary.parse(
          Lines.text(
            Lines.line("launch", at: 1), Lines.begin("a", "ranking", at: 9.5),
            Lines.line("heartbeat", at: 9.9))))
    }

    func capture(
      focused: FakeNode?, application: FakeNode? = nil, budget: TimeInterval = 5,
      limit: Int = 10_000
    ) -> TreeDump {
      TreeDump.capture(
        context, application: application ?? app, focusedWindow: { focused?.identity },
        clock: clock, budgetSeconds: budget, entryLimit: limit)
    }
  }

  func entry(_ dump: TreeDump, _ name: String) throws -> TreeDump.Entry {
    try #require(dump.entries.first { $0.identifier == name })
  }

  @Test func theHeaderDescribesTheFailureTheScopeAndTheTelemetry() {
    let fixture = Fixture()
    let dump = fixture.capture(focused: fixture.window)
    #expect(dump.version == 1)
    #expect(dump.action == 12)
    #expect(dump.request.kind == "setValue")
    #expect(dump.request.target == nil)
    #expect(dump.request.path == [0, 0, 20, 12])
    #expect(dump.request.role == "AXTextField")
    #expect(dump.request.label == "[0, 0, 20, 12]")
    #expect(dump.error == "Control not found: [0, 0, 20, 12]")
    #expect(dump.attempts == 3)
    #expect(dump.elapsedMilliseconds == 514)
    #expect(dump.scope == TreeDump.Scope(source: .focused, standardWindows: 2, selectedIndex: 0))
    #expect(dump.readErrors == 0)
    #expect(!dump.truncated)
    #expect(dump.truncatedReason == nil)
    #expect(
      dump.telemetry
        == TreeDump.Telemetry(
          events: 3, pendingWork: 1, openWork: ["ranking": 1], lastHeartbeatAgeMilliseconds: 100,
          lastActivityAgeMilliseconds: 500))
  }

  @Test func everyTopLevelChildIsListedAndOnlyTheScopeIsWalked() {
    let fixture = Fixture()
    let dump = fixture.capture(focused: fixture.window)
    #expect(dump.topLevel.map(\.index) == [0, 1, 2])
    #expect(dump.topLevel.map(\.role) == ["AXWindow", "AXWindow", "AXMenuBar"])
    #expect(dump.topLevel.map(\.subrole) == ["AXStandardWindow", "AXStandardWindow", ""])
    #expect(dump.topLevel.map(\.focused) == [true, false, false])
    #expect(dump.topLevel.map(\.inScope) == [true, false, true])
    #expect(dump.topLevel[0].title == "")
    #expect(dump.topLevel[0].identifier == "Typeface/Off")
    #expect(dump.topLevel[0].frame == [0, 0, 1000, 800])
    #expect(dump.topLevel[2].frame == nil)
    #expect(
      dump.entries.map(\.path) == [
        [0], [0, 0], [0, 1], [0, 2], [0, 3], [2], [2, 0], [2, 1], [2, 1, 0],
      ])
    #expect(dump.entries.allSatisfy { $0.identifier != "Other" })
  }

  @Test func hiddenDisabledClippedAndPrunedNodesAreMarkedNotOffered() throws {
    let fixture = Fixture()
    let dump = fixture.capture(focused: fixture.window)
    #expect(try entry(dump, "Typeface/Off").offered)
    let visible = try entry(dump, "Visible")
    #expect(visible.offered)
    #expect(visible.target == "Visible")
    #expect(visible.role == "AXButton")
    #expect(visible.frame == [10, 10, 100, 30])
    #expect(!(try entry(dump, "Hidden").offered))
    #expect(try entry(dump, "Hidden").hidden == true)
    #expect(!(try entry(dump, "Disabled").offered))
    #expect(try entry(dump, "Disabled").enabled == false)
    #expect(!(try entry(dump, "Clipped").offered))
    let minimize = try entry(dump, "Minimize")
    #expect(!minimize.offered)
    #expect(minimize.path == [2, 1, 0])
    let edit = try #require(dump.entries.first { $0.title == "Edit" })
    #expect(!edit.offered)
    #expect(edit.target == "Edit")
    #expect(edit.frame == nil)
  }

  @Test func aPopoverInFocusHidesTheWorkbenchFromDiscoveryButNotFromTheDump() throws {
    let fixture = Fixture()
    let world = fixture.world
    let popover = world.node(
      "AXWindow", subrole: "AXFloatingWindow", frame: FakeWorld.windowFrame,
      children: [world.node("AXButton", name: "In popover")])
    let application = world.application([popover, fixture.window, fixture.other])
    let dump = fixture.capture(focused: popover, application: application)
    #expect(dump.scope.source == .overlay)
    #expect(dump.scope.selectedIndex == 1)
    #expect(try entry(dump, "In popover").offered)
    #expect(!(try entry(dump, "Visible").offered))
    #expect(dump.topLevel.map(\.inScope) == [true, true, false])
  }

  @Test func anOpenSheetLimitsWhatIsOffered() throws {
    let fixture = Fixture()
    let world = fixture.world
    let sheet = world.node(
      "AXSheet", frame: FakeWorld.windowFrame,
      children: [world.node("AXButton", name: "On sheet")])
    let window = world.window(
      name: "Sheeted", children: [world.node("AXButton", name: "Behind"), sheet])
    let dump = fixture.capture(
      focused: window, application: world.application([window]))
    #expect(try entry(dump, "On sheet").offered)
    #expect(!(try entry(dump, "Behind").offered))
    #expect(!(try entry(dump, "Sheeted").offered))
    #expect(dump.entries.filter(\.offered).count == 2)
  }

  @Test func aSheetInsideAPrunedSubtreeDoesNotNarrowTheDump() throws {
    let fixture = Fixture()
    let world = fixture.world
    let sheet = world.node(
      "AXSheet", frame: FakeWorld.windowFrame,
      children: [world.node("AXButton", name: "Buried")])
    let window = world.window(
      name: "Pruned",
      children: [
        world.node("AXButton", name: "Front"),
        world.node("AXGroup", frame: nil, hidden: true, children: [sheet]),
      ])
    let dump = fixture.capture(focused: window, application: world.application([window]))
    #expect(try entry(dump, "Front").offered)
    #expect(try entry(dump, "Pruned").offered)
    #expect(!(try entry(dump, "Buried").offered))
    #expect(dump.entries.contains { $0.role == "AXSheet" })
  }

  @Test func aFocusHolderInsideAPrunedSubtreeIsNotTheModal() throws {
    let fixture = Fixture()
    let world = fixture.world
    let holder = world.node(
      "AXGroup", frame: nil, children: [world.node("AXButton", name: "Buried")])
    let sheet = world.node(
      "AXSheet", frame: FakeWorld.windowFrame,
      children: [world.node("AXButton", name: "On sheet")])
    let window = world.window(
      name: "Pruned",
      children: [world.node("AXGroup", frame: nil, hidden: true, children: [holder]), sheet])
    let dump = fixture.capture(focused: holder, application: world.application([window]))
    #expect(dump.scope.source == .overlay)
    #expect(try entry(dump, "On sheet").offered)
    #expect(!(try entry(dump, "Buried").offered))
  }

  @Test func anOverlayThatCannotBeLocatedOffersNothing() throws {
    let fixture = Fixture()
    let world = fixture.world
    let hidden = world.node(
      "AXSheet", frame: FakeWorld.windowFrame, hidden: true,
      children: [world.node("AXButton", name: "Inside")])
    let window = world.window(
      name: "Workbench", children: [world.node("AXButton", name: "Behind"), hidden])
    let dump = fixture.capture(focused: hidden, application: world.application([window]))
    #expect(dump.scope.source == .overlay)
    #expect(dump.entries.contains { $0.identifier == "Behind" })
    #expect(dump.entries.filter(\.offered).isEmpty)
  }

  @Test func aNodeReachedTwiceIsListedOnce() {
    let fixture = Fixture()
    let world = fixture.world
    let button = world.node("AXButton", name: "Twice")
    let window = world.window(children: [button, button])
    let dump = fixture.capture(focused: window, application: world.application([window]))
    #expect(dump.entries.filter { $0.identifier == "Twice" }.count == 1)
  }

  @Test func theEntryLimitTruncatesAndSaysSo() {
    let fixture = Fixture()
    let full = fixture.capture(focused: fixture.window)
    let exact = fixture.capture(focused: fixture.window, limit: full.entries.count)
    #expect(!exact.truncated)
    #expect(exact.entries == full.entries)
    let cut = fixture.capture(focused: fixture.window, limit: 2)
    #expect(cut.truncated)
    #expect(cut.truncatedReason == "limit")
    #expect(cut.entries.count == 2)
    #expect(cut.entries == Array(full.entries.prefix(2)))
  }

  @Test func theTimeBudgetTruncatesAndSaysSo() {
    let fixture = Fixture()
    fixture.world.clock = fixture.clock
    fixture.world.secondsPerRead = 1
    let dump = fixture.capture(focused: fixture.window, budget: 30)
    #expect(dump.truncated)
    #expect(dump.truncatedReason == "time")
    #expect(!dump.entries.isEmpty)
    #expect(dump.entries.count < 9)
    #expect(dump.scope.source == .focused)
  }

  @Test func readErrorsAreCarriedIntoTheDump() {
    let fixture = Fixture()
    fixture.world.readErrors = 2
    #expect(fixture.capture(focused: fixture.window).readErrors == 2)
  }

  @Test func aMissingFocusFallsBackToTheFrontMostWindow() {
    let fixture = Fixture()
    let dump = fixture.capture(focused: nil)
    #expect(dump.scope.source == .frontmost)
    #expect(dump.topLevel.map(\.focused) == [false, false, false])
    #expect(dump.topLevel.map(\.inScope) == [true, false, true])
  }

  @Test func candidatesAreTheEntriesThatShareARequestsRoleAndName() throws {
    let fixture = Fixture()
    let world = fixture.world
    let window = world.window(children: [
      world.node("AXSlider", name: "Font B Size"), world.node("AXSlider", name: "Font B Size"),
      world.node("AXButton", name: "Font B Size"), world.node("AXSlider", name: "Font A Size"),
      world.node("AXSlider", attributes: AccessibilityAttributes(help: "Font B Size")),
    ])
    let dump = fixture.capture(focused: window, application: world.application([window]))
    func request(_ target: String?, role: String?) -> ResolutionRequest {
      ResolutionRequest(
        FuzzAction(kind: .press, target: target, targetPath: [0], targetRole: role),
        allowVisibleTieBreak: false)
    }
    #expect(
      dump.candidates(for: request("Font B Size", role: "AXSlider")).map(\.path) == [
        [0, 0], [0, 1], [0, 4],
      ])
    #expect(dump.candidates(for: request("Font B Size", role: "AXButton")).map(\.path) == [[0, 2]])
    #expect(dump.candidates(for: request(nil, role: "AXSlider")).isEmpty)
    #expect(dump.candidates(for: request("Font B Size", role: nil)).isEmpty)
  }

  @Test func visibleElementsListRoleAndFirstNameInDocumentOrder() {
    let fixture = Fixture()
    let world = fixture.world
    let window = world.window(
      name: "Main",
      children: [
        world.node("AXButton", name: "Undo"), world.node("AXGroup"),
        world.node("", name: "Roleless"),
        world.node("AXSlider", attributes: AccessibilityAttributes(title: "Size", help: "Adjust")),
      ])
    let dump = fixture.capture(focused: window, application: world.application([window]))
    #expect(
      dump.visibleElements() == [
        "AXWindow:Main", "AXButton:Undo", "?:Roleless", "AXSlider:Adjust",
      ])
    #expect(dump.visibleElements(limit: 2) == ["AXWindow:Main", "AXButton:Undo"])
    #expect(dump.visibleElements(limit: 0).isEmpty)
  }

  @Test func theDumpEncodesItsDocumentedKeys() throws {
    let fixture = Fixture()
    let dump = fixture.capture(focused: fixture.window)
    let data = try JSONEncoder().encode(dump)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      Set(object.keys) == [
        "version", "action", "request", "error", "attempts", "elapsedMilliseconds", "scope",
        "topLevel", "telemetry", "readErrors", "truncated", "entries",
      ])
    let scope = try #require(object["scope"] as? [String: Any])
    #expect(scope["source"] as? String == "focused")
    #expect(scope["standardWindows"] as? Int == 2)
    #expect(scope["selectedIndex"] as? Int == 0)
    let entries = try #require(object["entries"] as? [[String: Any]])
    let visible = try #require(entries.first { $0["identifier"] as? String == "Visible" })
    #expect(visible["path"] as? [Int] == [0, 0])
    #expect(visible["frame"] as? [Double] == [10, 10, 100, 30])
    #expect(visible["offered"] as? Bool == true)
    #expect(visible["enabled"] == nil)
    let telemetry = try #require(object["telemetry"] as? [String: Any])
    #expect(telemetry["openWork"] as? [String: Int] == ["ranking": 1])
    let cut = try JSONEncoder().encode(fixture.capture(focused: fixture.window, limit: 1))
    let truncated = try #require(JSONSerialization.jsonObject(with: cut) as? [String: Any])
    #expect(truncated["truncated"] as? Bool == true)
    #expect(truncated["truncatedReason"] as? String == "limit")
  }

  @Test func theDumpIsSavedAsPrettyJsonAndReplacedInPlace() throws {
    let fixture = Fixture()
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "tree-dump-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "runs/one/diagnostics-1.json")
    try TraceIO.save(fixture.capture(focused: fixture.window), to: url)
    try TraceIO.save(fixture.capture(focused: fixture.window, limit: 1), to: url)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("\n  \"action\" : 12"))
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    #expect(object["truncated"] as? Bool == true)
    #expect(object["version"] as? Int == 1)
  }

  @Test func nonFiniteFramesArePreservedInSavedDiagnostics() throws {
    let fixture = Fixture()
    fixture.other.frame = CGRect(x: -.infinity, y: .nan, width: .infinity, height: 30)
    fixture.window.childNodes.append(
      fixture.world.node("AXButton", name: "Null frame", frame: .null))
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "tree-dump-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "diagnostics.json")
    try TraceIO.save(fixture.capture(focused: fixture.window), to: url)
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let topLevel = try #require(object["topLevel"] as? [[String: Any]])
    let otherFrame = try #require(topLevel[1]["frame"] as? [Any])
    #expect(otherFrame.count == 4)
    #expect(otherFrame[0] as? String == "-Infinity")
    #expect(otherFrame[1] as? String == "NaN")
    #expect(otherFrame[2] as? String == "Infinity")
    #expect(otherFrame[3] as? Double == 30)
    let entries = try #require(object["entries"] as? [[String: Any]])
    let invalid = try #require(entries.first { $0["identifier"] as? String == "Null frame" })
    let nullFrame = try #require(invalid["frame"] as? [Any])
    #expect(nullFrame.count == 4)
    #expect(nullFrame[0] as? String == "Infinity")
    #expect(nullFrame[1] as? String == "Infinity")
    #expect(nullFrame[2] as? Double == 0)
    #expect(nullFrame[3] as? Double == 0)
    #expect(invalid["offered"] as? Bool == false)
    let visible = try #require(entries.first { $0["identifier"] as? String == "Visible" })
    #expect(visible["frame"] as? [Double] == [10, 10, 100, 30])
    #expect(object["error"] as? String == fixture.context.error)
  }
}

@Suite struct DriverLogTests {
  static func directory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "driver-log-\(UUID().uuidString)")
  }

  @Test func aMinimalEventHasOnlyItsRequiredKeysInSortedOrder() throws {
    let line = try DriverLog.line(DriverEvent(uptime: 12.5, event: .idle))
    #expect(line == "{\"event\":\"idle\",\"uptime\":12.5}")
    let several = try DriverLog.line(
      DriverEvent(uptime: 2, event: .resolve, step: .path, attempts: 1))
    #expect(several == "{\"attempts\":1,\"event\":\"resolve\",\"step\":\"path\",\"uptime\":2}")
  }

  @Test func aFullEventEncodesEveryFieldAndNothingIsRenamed() throws {
    let event = DriverEvent(
      uptime: 100.25, event: .resolve, action: 3, control: "AXButton Reset",
      step: .uniqueName, attempts: 2, waitedMs: 30, timedOut: false, pendingWork: 1,
      openWork: ["ranking": 1], windows: 2, scope: .overlay, elements: 40, elapsedMs: 12.5,
      skipped: true, focusedRole: "AXSheet", focusedSubrole: "AXSystemDialog",
      focusLocation: .scopeWindow, modalRole: "AXSheet", modalDepth: 2, unlocated: true,
      context: "match")
    let line = try DriverLog.line(event)
    #expect(!line.contains("\n"))
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    #expect(
      Set(object.keys) == [
        "uptime", "event", "action", "control", "step", "attempts", "waitedMs", "timedOut",
        "pendingWork", "openWork", "windows", "scope", "elements", "elapsedMs", "skipped",
        "focusedRole", "focusedSubrole", "focusLocation", "modalRole", "modalDepth", "unlocated",
        "context",
      ])
    #expect(object["focusedRole"] as? String == "AXSheet")
    #expect(object["focusedSubrole"] as? String == "AXSystemDialog")
    #expect(object["focusLocation"] as? String == "scopeWindow")
    #expect(object["modalRole"] as? String == "AXSheet")
    #expect(object["modalDepth"] as? Int == 2)
    #expect(object["unlocated"] as? Bool == true)
    #expect(object["context"] as? String == "match")
    #expect(object["event"] as? String == "resolve")
    #expect(object["step"] as? String == "uniqueName")
    #expect(object["scope"] as? String == "overlay")
    #expect(object["openWork"] as? [String: Int] == ["ranking": 1])
    #expect(object["timedOut"] as? Bool == false)
    #expect(object["elapsedMs"] as? Double == 12.5)
    #expect(object["skipped"] as? Bool == true)
  }

  @Test func aDiscoverEventWithoutFocusOrModalOmitsThoseFields() throws {
    let line = try DriverLog.line(
      DriverEvent(uptime: 3, event: .discover, windows: 1, scope: .frontmost, elements: 144))
    #expect(
      line
        == "{\"elements\":144,\"event\":\"discover\",\"scope\":\"frontmost\",\"uptime\":3,\"windows\":1}"
    )
  }

  @Test func anIdleEventCarriesTheWaitOrOnlyThatItWasSkipped() throws {
    let waited = IdleWaitResult(
      seconds: 0.25, timedOut: true, skipped: false,
      openWork: ["ranking": 2, "feature-preview": 1])
    let waitedLine = try DriverLog.line(.idle(waited, uptime: 9, action: 4))
    let waitedObject = try #require(
      JSONSerialization.jsonObject(with: Data(waitedLine.utf8)) as? [String: Any])
    #expect(
      Set(waitedObject.keys) == [
        "uptime", "event", "action", "waitedMs", "timedOut", "pendingWork", "openWork",
      ])
    #expect(waitedObject["event"] as? String == "idle")
    #expect(waitedObject["action"] as? Int == 4)
    #expect(waitedObject["waitedMs"] as? Double == 250)
    #expect(waitedObject["timedOut"] as? Bool == true)
    #expect(waitedObject["pendingWork"] as? Int == 3)
    #expect(waitedObject["openWork"] as? [String: Int] == ["ranking": 2, "feature-preview": 1])

    let skipped = IdleWaitResult(seconds: 0, timedOut: false, skipped: true, openWork: [:])
    #expect(
      try DriverLog.line(.idle(skipped, uptime: 9, action: 4))
        == "{\"action\":4,\"event\":\"idle\",\"skipped\":true,\"uptime\":9}")
  }

  @Test func everyEventKindHasItsOwnName() throws {
    let kinds: [DriverEvent.Kind] = [.idle, .discover, .resolve, .skip, .fail]
    let lines = try kinds.map { try DriverLog.line(DriverEvent(uptime: 1, event: $0)) }
    #expect(
      lines == [
        "{\"event\":\"idle\",\"uptime\":1}", "{\"event\":\"discover\",\"uptime\":1}",
        "{\"event\":\"resolve\",\"uptime\":1}", "{\"event\":\"skip\",\"uptime\":1}",
        "{\"event\":\"fail\",\"uptime\":1}",
      ])
  }

  @Test func eventsAreAppendedOneLineEachAcrossReopenings() throws {
    let directory = Self.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "runs/one/driver.jsonl")
    let first = try DriverLog.open(url)
    try DriverLog.append(DriverEvent(uptime: 1, event: .discover, elements: 12), to: first)
    try DriverLog.append(DriverEvent(uptime: 2, event: .resolve, step: .path), to: first)
    try first.close()
    let second = try DriverLog.open(url)
    try DriverLog.append(DriverEvent(uptime: 3, event: .skip, action: 4), to: second)
    try second.close()
    let lines = try String(contentsOf: url, encoding: .utf8).split(
      separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 4)
    #expect(lines.last == "")
    let events = try lines.dropLast().map { line -> String? in
      let object = try #require(
        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
      return object["event"] as? String
    }
    #expect(events == ["discover", "resolve", "skip"])
  }
}
