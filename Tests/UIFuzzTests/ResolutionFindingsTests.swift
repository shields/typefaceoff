import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct ResolutionFindingsTests {
  typealias Lines = TelemetryLines

  static let press = FuzzAction(
    kind: .press, target: "Font B Size", targetPath: [0, 0, 20, 7], targetRole: "AXSlider")

  static func failure(
    _ error: any Error, reason: TerminalReason, request: ResolutionRequest? = nil
  ) -> SlotFailure {
    SlotFailure(
      action: press, request: request ?? ResolutionRequest(press, allowVisibleTieBreak: true),
      underlying: error, reason: reason, skipSeconds: 0)
  }

  static func entry(
    _ path: [Int], role: String = "AXSlider", identifier: String = "Font B Size",
    title: String = "", help: String = ""
  ) -> TreeDump.Entry {
    TreeDump.Entry(
      path: path, role: role, subrole: "", identifier: identifier, title: title,
      description: "", help: help, frame: nil, enabled: nil, hidden: nil, offered: true,
      target: [identifier, title].first { !$0.isEmpty })
  }

  static let busy = TelemetrySummary.parse(
    Lines.text(
      Lines.begin("a", "ranking", at: 1), Lines.begin("b", "feature-preview", at: 1.1),
      Lines.begin("c", "ranking", at: 1.2)))

  static func detail(_ change: (inout ResolutionFindings.Detail) -> Void = { _ in })
    -> ResolutionFindings.Detail
  {
    var detail = ResolutionFindings.Detail(
      action: 12, error: "Control not found: [0, 0, 20, 7]", attempts: 3,
      elapsedMilliseconds: 514, telemetry: TelemetrySummary())
    change(&detail)
    return detail
  }

  @Test func theSignatureOfAMissingControlIsTheOneEarlierCampaignsUsed() {
    let missing = Self.failure(ResolutionFailure.missing("[0, 0, 20, 7]"), reason: .disabled)
    #expect(ResolutionFindings.signature(for: missing) == "Control not found: [0, 0, 20, 7]")
    let nameless = Self.failure(
      ResolutionFailure(kind: .missing(.noTarget), label: "<missing target>"),
      reason: .recordedAction)
    #expect(ResolutionFindings.signature(for: nameless) == "Control not found: <missing target>")
  }

  @Test func anAmbiguousControlHasItsOwnSignatureWithoutCounts() {
    let ambiguous = Self.failure(
      ResolutionFailure(kind: .ambiguous(matches: 3, offered: 2), label: "Reset typography"),
      reason: .repeatedInRun)
    #expect(ResolutionFindings.signature(for: ambiguous) == "Ambiguous control: Reset typography")
  }

  @Test func aPersistentControlIsNamedByItsKey() {
    let persistent = Self.failure(
      ResolutionFailure.missing("Font B Size"),
      reason: .persistent(key: "AXSlider Font B Size", consecutive: 3, failures: 3, attempts: 3))
    #expect(
      ResolutionFindings.signature(for: persistent)
        == "Persistent stale control: AXSlider Font B Size"
    )
  }

  @Test func anyOtherErrorKeepsItsOwnDescription() {
    struct Custom: Error, CustomStringConvertible {
      var description: String { "Accessibility action AXPress failed: -25200" }
    }
    let other = Self.failure(Custom(), reason: .notSkippable)
    #expect(
      ResolutionFindings.signature(for: other) == "Accessibility action AXPress failed: -25200")
  }

  @Test func theSmallestDetailReadsAsOneLineEndingWithTheElementList() {
    #expect(
      ResolutionFindings.detail(Self.detail())
        == "Action 12: Control not found: [0, 0, 20, 7]. Attempts: 3 over 514 ms. "
        + "Pending work: none. Visible accessibility elements: ")
  }

  @Test func theFullDetailHasEveryClauseInOrder() {
    let scope = TreeDump.Scope(source: .focused, standardWindows: 2, selectedIndex: 0)
    let text = ResolutionFindings.detail(
      Self.detail {
        $0.reason = "No control matched in the scope window"
        $0.telemetry = Self.busy
        $0.scope = scope
        $0.candidates = [Self.entry([0, 0, 19, 9]), Self.entry([1, 0, 19, 9], identifier: "")]
        $0.skipped = [
          SkippedAction(
            slot: 3, kind: "press", key: "AXTextField <unnamed>",
            runKey: "AXTextField [0, 0, 20, 7]", signature: "x"),
          SkippedAction(
            slot: 5, kind: "scroll", key: "AXScrollArea <unnamed>",
            runKey: "AXScrollArea [0, 1]", signature: "y"),
        ]
        $0.stopReason = .consecutiveBudget
        $0.diagnostics = "runs/abc/diagnostics-2.json"
        $0.visibleElements = ["AXButton:Undo", "AXSlider:Font A Size"]
      })
    #expect(
      text
        == "Action 12: Control not found: [0, 0, 20, 7]. No control matched in the scope window. "
        + "Attempts: 3 over 514 ms. Pending work: feature-preview×1, ranking×2. "
        + "Scope: focused, window child 0, standard windows: 2. "
        + "Ambiguous candidates: [0, 0, 19, 9] AXSlider \"Font B Size\"; [1, 0, 19, 9] AXSlider \"\". "
        + "Skipped earlier: 2 (AXTextField <unnamed>; AXScrollArea <unnamed>). "
        + "Stop reason: too many skips in a row. "
        + "Diagnostics: runs/abc/diagnostics-2.json. "
        + "Visible accessibility elements: AXButton:Undo, AXSlider:Font A Size")
    #expect(!text.contains("\n"))
  }

  @Test func aScopeWithoutAWindowSaysSo() {
    let scope = TreeDump.Scope(source: .none, standardWindows: 0, selectedIndex: nil)
    let text = ResolutionFindings.detail(Self.detail { $0.scope = scope })
    #expect(text.contains("Scope: none, no window, standard windows: 0. "))
  }

  @Test func theCandidateListStopsAtEightAndCountsTheRest() {
    let candidates = (0..<11).map { Self.entry([0, $0]) }
    let text = ResolutionFindings.detail(Self.detail { $0.candidates = candidates })
    #expect(text.contains("[0, 7] AXSlider \"Font B Size\" (+3 more). "))
    #expect(!text.contains("[0, 8]"))
    let exact = ResolutionFindings.detail(
      Self.detail { $0.candidates = Array(candidates.prefix(8)) })
    #expect(exact.contains("[0, 7] AXSlider \"Font B Size\". "))
  }

  @Test func aCandidateWithNoDiscoveryTargetIsNamedByItsFirstName() {
    let entry = Self.entry([0, 1], identifier: "", help: "Adjust size")
    let text = ResolutionFindings.detail(Self.detail { $0.candidates = [entry] })
    #expect(text.contains("[0, 1] AXSlider \"Adjust size\". "))
  }

  @Test func theElementListIsCutAtOneHundred() {
    let visible = (0..<130).map { "AXButton:Button \($0)" }
    let text = ResolutionFindings.detail(Self.detail { $0.visibleElements = visible })
    #expect(text.hasSuffix("AXButton:Button 98, AXButton:Button 99"))
    let list = text.components(separatedBy: "Visible accessibility elements: ")[1]
    #expect(list.components(separatedBy: ", ").count == 100)
  }

  @Test func everyStopReasonHasText() {
    let reasons: [(TerminalReason, String)] = [
      (.disabled, "skipping is disabled"),
      (
        .persistent(key: "AXButton Reset", consecutive: 3, failures: 5, attempts: 8),
        "AXButton Reset is persistently missing (3 consecutive, 5 of 8 attempts failed)"
      ),
      (.repeatedInRun, "the same control failed again in this run"),
      (.consecutiveBudget, "too many skips in a row"),
      (.runBudget, "the skip budget of the run is spent"),
      (.notSkippable, "the failure cannot be skipped"),
      (.recordedAction, "the action was recorded, so it never skips"),
    ]
    for (reason, text) in reasons { #expect(reason.text == text) }
  }

  @Test func aResolutionFailureIsAnAutomationFinding() {
    let failure = Self.failure(ResolutionFailure.missing("[0, 0, 20, 7]"), reason: .recordedAction)
    let finding = ResolutionFindings.finding(for: failure, detail: Self.detail())
    #expect(finding.kind == .automation)
    #expect(finding.signature == "Control not found: [0, 0, 20, 7]")
    #expect(finding.detail == ResolutionFindings.detail(Self.detail()))
    #expect(!finding.isSideFileFailure)
  }

  @Test func aSideFileThatCannotBeWrittenIsAFindingOfItsOwn() {
    struct Full: Error, CustomStringConvertible {
      var description: String { "no space left" }
    }
    let diagnostics = ResolutionFindings.sideFileFailure(.diagnostics, error: Full())
    #expect(diagnostics.kind == .automation)
    #expect(diagnostics.signature == "diagnostics-write")
    #expect(diagnostics.detail == "Could not write a diagnostics file: no space left")
    let log = ResolutionFindings.sideFileFailure(.driverLog, error: Full())
    #expect(log.signature == "driver-log-write")
    #expect(log.detail == "Could not write the driver log: no space left")
    #expect(diagnostics.isSideFileFailure && log.isSideFileFailure)
  }

  @Test func thePrimaryFindingIsAlwaysFirstAndMinimizeTargetsIt() {
    let side = ResolutionFindings.sideFileFailure(
      .diagnostics, error: CocoaError(.fileWriteUnknown))
    let log = ResolutionFindings.sideFileFailure(.driverLog, error: CocoaError(.fileWriteUnknown))
    let primary = ExecutionFinding(
      kind: .automation, signature: "Control not found: Font B Size", detail: "d")
    let hang = ExecutionFinding(kind: .hang, signature: "completion-timeout", detail: "h")
    let ordered = ResolutionFindings.ordered([side, primary, log, hang])
    #expect(ordered == [primary, hang, side, log])
    #expect(ResolutionFindings.ordered([]).isEmpty)
    #expect(ordered.first?.reproduces(primary) == true)
  }

  @Test func metadataCountsStepsRetriesAndDiagnostics() throws {
    var metadata = ResolutionMetadata()
    #expect(metadata.stepSummary.isEmpty)
    metadata.recordResolution(attempts: 1, step: .path)
    metadata.recordResolution(attempts: 2, step: .path)
    metadata.recordResolution(attempts: 3, step: .uniqueName)
    metadata.recordResolution(attempts: 1, step: .firstName)
    metadata.recordResolution(attempts: 3, step: nil)
    #expect(metadata.retries == 3)
    #expect(metadata.stepSummary == "path:2 uniqueName:1 firstName:1")
    metadata.recordDiagnostics("diagnostics-1.json")
    metadata.recordDiagnostics("diagnostics-2.json")
    metadata.stopReason = .runBudget
    metadata.idleGated = true

    let skip = SkippedAction(
      slot: 4, kind: "press", key: "AXButton Reset", runKey: "AXButton Reset", signature: "s",
      diagnostics: "diagnostics-1.json")
    var idle = IdleBudget()
    var tail = TelemetryTail()
    _ = IdleWait.run(
      since: 0, quiescence: 0.2, clock: FakeClock(), tail: &tail, budget: &idle,
      read: { _ in Data() })
    let entries = metadata.entries(skips: [skip], idle: idle)
    #expect(entries["skipped-actions"] == "1")
    #expect(entries["resolve-retries"] == "3")
    #expect(entries["resolution-steps"] == "path:2 uniqueName:1 firstName:1")
    #expect(entries["diagnostics"] == "diagnostics-1.json,diagnostics-2.json")
    #expect(entries["stop-reason"] == "the skip budget of the run is spent")
    #expect(entries["live-idle-gated"] == "true")
    #expect(entries["idle-wait-timeouts"] == "1")
    #expect(entries["idle-waits"] == "1")
    #expect(entries["idle-wait-skipped"] == "0")
    #expect(entries["idle-wait-ms"] == String(idle.spent * 1000))
    let json = try #require(entries["skips"])
    let decoded = try JSONDecoder().decode([SkippedAction].self, from: Data(json.utf8))
    #expect(decoded == [skip])
  }

  @Test func metadataOfAQuietRunHasOnlyTheCounters() {
    let entries = ResolutionMetadata().entries(skips: [], idle: nil)
    #expect(entries == ["skipped-actions": "0", "resolve-retries": "0"])
  }

  @Test func theProgressLineMentionsSkipsOnlyWhenThereWereSome() {
    #expect(ResolutionMetadata.progressSuffix(skips: 0).isEmpty)
    #expect(ResolutionMetadata.progressSuffix(skips: 3) == " skips=3")
  }
}
