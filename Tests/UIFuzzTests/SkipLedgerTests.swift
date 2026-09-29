import Foundation
import Testing

@testable import UIFuzzSupport

private func request(
  _ role: String = "AXButton", target: String? = "Reset", path: [Int]? = [0, 1]
) -> ResolutionRequest {
  ResolutionRequest(
    FuzzAction(kind: .press, target: target, targetPath: path, targetRole: role),
    allowVisibleTieBreak: true)
}

private func named(_ index: Int) -> ResolutionRequest { request(target: "Control \(index)") }

private func unnamed(_ path: [Int]) -> ResolutionRequest {
  request("AXTextField", target: nil, path: path)
}

extension SkipLedger {
  fileprivate mutating func fail(_ request: ResolutionRequest, slot: Int = 1) -> SkipDecision {
    failed(request, slot: slot, kind: "press", signature: "Control not found: \(request.label)")
  }

  /// One event per character: `F` fails the request in a run of its own, `S` succeeds it.
  fileprivate mutating func play(_ pattern: String, _ request: ResolutionRequest) -> SkipDecision? {
    var last: SkipDecision?
    for event in pattern {
      beginRun()
      if event == "F" {
        last = fail(request)
      } else {
        succeeded(request)
      }
    }
    return last
  }
}

@Suite struct SkipLedgerTests {
  static let persistentKey = "AXButton Reset"

  @Test func aSkipRecordsTheActionAndASuccessResetsTheRun() {
    var ledger = SkipLedger()
    ledger.beginRun()
    let decision = ledger.failed(
      named(1), slot: 7, kind: "press", signature: "Control not found: Control 1")
    let skipped = SkippedAction(
      slot: 7, kind: "press", key: "AXButton Control 1", runKey: "AXButton Control 1",
      signature: "Control not found: Control 1")
    #expect(decision == .skip(skipped))
    #expect(ledger.skips == [skipped])
    ledger.succeeded(named(2))
    #expect(ledger.fail(named(3)) != .terminal(.consecutiveBudget))
    #expect(ledger.skips.count == 2)
  }

  @Test func aThirdFailureInARowIsTerminal() {
    var ledger = SkipLedger()
    ledger.beginRun()
    #expect(ledger.fail(named(1)) != .terminal(.consecutiveBudget))
    #expect(ledger.fail(named(2)) != .terminal(.consecutiveBudget))
    #expect(ledger.fail(named(3)) == .terminal(.consecutiveBudget))
    #expect(ledger.skips.count == 2)
  }

  @Test func theRunBudgetEndsTheSixthFailure() {
    var ledger = SkipLedger()
    ledger.beginRun()
    for index in 1...5 {
      if index > 1 && index % 2 == 1 { ledger.succeeded(nil) }
      guard case .skip = ledger.fail(named(index)) else {
        Issue.record("failure \(index) should have been skipped")
        return
      }
    }
    #expect(ledger.skips.count == 5)
    ledger.succeeded(nil)
    #expect(ledger.fail(named(6)) == .terminal(.runBudget))
    #expect(ledger.skips.count == 5)
  }

  @Test func aControlMayBeSkippedOncePerRunUnlessThePolicyAllowsMore() {
    var ledger = SkipLedger()
    ledger.beginRun()
    guard case .skip = ledger.fail(named(1)) else {
      Issue.record("the first failure should be skipped")
      return
    }
    ledger.succeeded(named(2))
    #expect(ledger.fail(named(1)) == .terminal(.repeatedInRun))
    ledger.succeeded(named(1))
    ledger.beginRun()
    guard case .skip = ledger.fail(named(1)) else {
      Issue.record("a new run starts with no skipped controls")
      return
    }

    var lenient = SkipLedger()
    lenient.policy.maximumPerControlPerRun = 2
    lenient.beginRun()
    #expect(lenient.fail(named(1)) != .terminal(.repeatedInRun))
    lenient.succeeded(named(1))
    #expect(lenient.fail(named(1)) != .terminal(.repeatedInRun))
    lenient.succeeded(named(1))
    #expect(lenient.fail(named(1)) == .terminal(.repeatedInRun))
  }

  @Test func aSuccessResetsConsecutiveFailuresButNotTheTotals() {
    var ledger = SkipLedger()
    ledger.beginRun()
    _ = ledger.fail(named(1))
    #expect(ledger.controls["AXButton Control 1"]?.consecutive == 1)
    ledger.succeeded(named(1))
    let stats = ledger.controls["AXButton Control 1"]
    #expect(stats?.consecutive == 0)
    #expect(stats?.failures == 1)
    #expect(stats?.attempts == 2)
  }

  @Test func aPickWithoutAControlResetsOnlyTheRunsConsecutiveSkips() {
    var ledger = SkipLedger()
    ledger.beginRun()
    _ = ledger.fail(named(1))
    _ = ledger.fail(named(2))
    ledger.succeeded(nil)
    #expect(ledger.controls.count == 2)
    #expect(ledger.fail(named(3)) != .terminal(.consecutiveBudget))
  }

  @Test func aNamedControlIsPersistentAfterThreeFailuresInARow() {
    var ledger = SkipLedger()
    #expect(ledger.play("FF", request()) != .terminal(.repeatedInRun))
    #expect(
      ledger.play("F", request())
        == .terminal(
          .persistent(key: Self.persistentKey, consecutive: 3, failures: 3, attempts: 3)))
    #expect(ledger.controls[Self.persistentKey]?.reported == true)
  }

  @Test func aPersistentControlIsReportedOnceAndThenOnlyBoundedByTheRunBudgets() {
    var ledger = SkipLedger()
    _ = ledger.play("FFF", request())
    guard case .skip = ledger.play("F", request()) else {
      Issue.record("a reported control follows only the per-run budgets")
      return
    }
    ledger.beginRun()
    #expect(ledger.fail(request()) != .terminal(.consecutiveBudget))
    #expect(ledger.fail(request()) == .terminal(.repeatedInRun))
  }

  @Test func aControlThatFailsHalfOfItsAttemptsIsPersistentAtTheBoundary() {
    var atHalf = SkipLedger()
    let decision = atHalf.play("SSSFFSFFSF", request())
    #expect(
      decision
        == .terminal(
          .persistent(key: Self.persistentKey, consecutive: 1, failures: 5, attempts: 10)))

    var belowHalf = SkipLedger()
    guard case .skip = belowHalf.play("SSSFFSFFSSF", request()) else {
      Issue.record("5 of 11 attempts is under the rate")
      return
    }

    var fewFailures = SkipLedger()
    guard case .skip = fewFailures.play("FSFSFSFS", request()) else {
      Issue.record("4 failures are under the count")
      return
    }
  }

  @Test func aPooledUnnamedControlIsPersistentOnlyByRate() {
    var ledger = SkipLedger()
    guard case .skip = ledger.play("FFFF", unnamed([0, 0, 20, 7])) else {
      Issue.record("unnamed controls do not count consecutive failures")
      return
    }
    #expect(ledger.controls["AXTextField <unnamed>"]?.consecutive == 4)
    #expect(
      ledger.play("F", unnamed([0, 0, 20, 8]))
        == .terminal(
          .persistent(key: "AXTextField <unnamed>", consecutive: 5, failures: 5, attempts: 5)))
  }

  @Test func anUnnamedControlIsToldApartByItsPathWithinARun() {
    var ledger = SkipLedger()
    ledger.beginRun()
    guard case .skip(let first) = ledger.fail(unnamed([0, 0, 20, 7])) else {
      Issue.record("the first unnamed failure should be skipped")
      return
    }
    #expect(first.key == "AXTextField <unnamed>")
    #expect(first.runKey == "AXTextField [0, 0, 20, 7]")
    ledger.succeeded(nil)
    guard case .skip = ledger.fail(unnamed([0, 0, 20, 8])) else {
      Issue.record("another path is another control within the run")
      return
    }
    ledger.succeeded(nil)
    #expect(ledger.fail(unnamed([0, 0, 20, 7])) == .terminal(.repeatedInRun))
  }

  @Test func aZeroRunBudgetRestoresFailFast() {
    var ledger = SkipLedger(policy: SkipPolicy(maximumPerRun: 0))
    ledger.beginRun()
    #expect(ledger.fail(named(1)) == .terminal(.disabled))
    #expect(ledger.skips.isEmpty)
    #expect(ledger.controls["AXButton Control 1"]?.failures == 1)
    #expect(ledger.play("FFF", request()) == .terminal(.disabled))
    #expect(ledger.controls[Self.persistentKey]?.reported == false)
  }

  @Test func beginningARunKeepsTheCampaignCounters() {
    var ledger = SkipLedger()
    ledger.beginRun()
    _ = ledger.fail(named(1))
    ledger.beginRun()
    #expect(ledger.skips.isEmpty)
    #expect(ledger.controls["AXButton Control 1"]?.failures == 1)
  }

  @Test func diagnosticsAttachToTheLatestSkip() {
    var ledger = SkipLedger()
    ledger.beginRun()
    _ = ledger.fail(named(1))
    ledger.recordDiagnostics("diagnostics-1.json")
    #expect(ledger.skips.last?.diagnostics == "diagnostics-1.json")
  }

  @Test func theLedgerRoundTripsWithoutItsPolicyOrItsRun() throws {
    var ledger = SkipLedger(appFingerprint: "app@1#2", policy: SkipPolicy(maximumPerRun: 9))
    _ = ledger.play("FFF", request())
    ledger.beginRun()
    _ = ledger.fail(named(4))
    ledger.recordDiagnostics("diagnostics-1.json")
    let data = try JSONEncoder().encode(ledger)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["appFingerprint", "controls"])
    let decoded = try JSONDecoder().decode(SkipLedger.self, from: data)
    #expect(decoded.appFingerprint == "app@1#2")
    #expect(decoded.controls == ledger.controls)
    #expect(decoded.policy == SkipPolicy())
    #expect(decoded.skips.isEmpty)
    #expect(decoded.controls[Self.persistentKey]?.reported == true)
  }

  @Test func aSkippedActionRoundTrips() throws {
    let skipped = SkippedAction(
      slot: 3, kind: "scroll", key: "AXScrollArea <unnamed>", runKey: "AXScrollArea [0, 2]",
      signature: "Control not found: [0, 2]", diagnostics: "diagnostics-1.json")
    let data = try JSONEncoder().encode(skipped)
    #expect(try JSONDecoder().decode(SkippedAction.self, from: data) == skipped)
  }

  @Test func theFingerprintNamesThePathTheModificationTimeAndTheSize() {
    #expect(
      SkipLedger.fingerprint(path: "/a/TypefaceOff.app", modified: 1234.5678, size: 99)
        == "/a/TypefaceOff.app@1234568#99")
    #expect(
      SkipLedger.fingerprint(path: "/a", modified: 1, size: 2)
        != SkipLedger.fingerprint(path: "/a", modified: 1, size: 3))
  }

  @Test func aLedgerIsKeptOnlyForTheSameAppAndWithoutAResetRequest() {
    var old = SkipLedger(appFingerprint: "one")
    _ = old.play("F", request())
    let policy = SkipPolicy(maximumPerRun: 3)

    let fresh = SkipLedger.opening(
      existing: nil, appFingerprint: "one", reset: false, policy: policy)
    #expect(fresh.ledger == SkipLedger(appFingerprint: "one", policy: policy))
    #expect(fresh.notice == nil)

    let kept = SkipLedger.opening(
      existing: old, appFingerprint: "one", reset: false, policy: policy)
    #expect(kept.ledger.controls == old.controls)
    #expect(kept.ledger.policy == policy)
    #expect(kept.notice == nil)

    let reset = SkipLedger.opening(
      existing: old, appFingerprint: "one", reset: true, policy: policy)
    #expect(reset.ledger == SkipLedger(appFingerprint: "one", policy: policy))
    #expect(reset.notice == "Started an empty skip ledger because --reset-skip-ledger was given.")

    let rebuilt = SkipLedger.opening(
      existing: old, appFingerprint: "two", reset: false, policy: policy)
    #expect(rebuilt.ledger == SkipLedger(appFingerprint: "two", policy: policy))
    #expect(
      rebuilt.notice == "Started an empty skip ledger because the app changed since it was written."
    )
  }

  @Test func theLedgerIsSavedAndLoadedFromDisk() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "skip-ledger-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "nested/skip-ledger.json")
    #expect(try SkipLedger.load(from: url) == nil)

    var ledger = SkipLedger(appFingerprint: "app")
    _ = ledger.play("FSF", request())
    try ledger.save(to: url)
    let loaded = try #require(try SkipLedger.load(from: url))
    #expect(loaded.controls == ledger.controls)
    #expect(loaded.appFingerprint == "app")

    try Data("not json".utf8).write(to: url)
    #expect(throws: DecodingError.self) { try SkipLedger.load(from: url) }
  }

  @Test func theSummaryListsTheWorstControlsFirst() {
    var ledger = SkipLedger()
    _ = ledger.play("FSF", named(1))
    _ = ledger.play("FS", named(2))
    _ = ledger.play("F", named(3))
    _ = ledger.play("SS", named(4))
    #expect(
      ledger.summary() == [
        "AXButton Control 1: 2 failed of 3 attempts", "AXButton Control 2: 1 failed of 2 attempts",
        "AXButton Control 3: 1 failed of 1 attempts",
      ])
    #expect(ledger.summary(limit: 1) == ["AXButton Control 1: 2 failed of 3 attempts"])
    #expect(SkipLedger().summary().isEmpty)
  }
}

@Suite struct SlotResolutionTests {
  struct Missing: Error {}

  final class Script {
    let clock = FakeClock()
    var picks: [FuzzAction]
    var began: [FuzzAction] = []
    var resolved: [(request: ResolutionRequest, retry: ResolutionRetry)] = []
    var since: [TimeInterval] = []
    var skipped: [(SkippedAction, ResolutionFailure)] = []
    var failures: [String: any Error] = [:]
    var diagnostics: String? = "diagnostics-1.json"
    var skipCost = 0.2

    init(_ picks: [FuzzAction]) { self.picks = picks }

    func pick(_ since: TimeInterval) -> FuzzAction {
      self.since.append(since)
      return picks.removeFirst()
    }

    func begin(_ action: FuzzAction) { began.append(action) }

    func resolve(_ request: ResolutionRequest, _ retry: ResolutionRetry) throws -> String {
      resolved.append((request, retry))
      if let error = failures[request.label] { throw error }
      return "element \(request.label)"
    }

    func didSkip(_ skip: SkippedAction, _ failure: ResolutionFailure) -> String? {
      skipped.append((skip, failure))
      clock.advance(skipCost)
      return diagnostics
    }
  }

  static func press(_ target: String) -> FuzzAction {
    FuzzAction(kind: .press, target: target, targetPath: [0, 1], targetRole: "AXButton")
  }

  static let shortcut = FuzzAction(kind: .shortcut, keyCode: 45)

  func live(
    _ script: Script, ledger: inout SkipLedger, slot: Int = 4, since: TimeInterval = 1.5
  ) throws -> ResolvedSlot<String> {
    try resolveLiveSlot(
      slot: slot, since: since, ledger: &ledger, clock: script.clock, pick: script.pick,
      begin: script.begin, resolve: script.resolve, didSkip: script.didSkip)
  }

  func thrown(_ body: () throws -> some Any) -> (any Error)? {
    do {
      _ = try body()
      return nil
    } catch {
      return error
    }
  }

  func slotFailure(_ body: () throws -> some Any) -> SlotFailure? {
    thrown(body) as? SlotFailure
  }

  func near(_ actual: TimeInterval?, _ expected: TimeInterval) -> Bool {
    actual.map { abs($0 - expected) < 1e-9 } ?? false
  }

  @Test func aLivePickThatResolvesIsReturnedWithItsRequest() throws {
    let script = Script([Self.press("Reset")])
    var ledger = SkipLedger()
    let slot = try live(script, ledger: &ledger)
    #expect(slot.action == Self.press("Reset"))
    #expect(slot.target == "element Reset")
    #expect(slot.skipSeconds == 0)
    let request = try #require(slot.request)
    #expect(request.allowVisibleTieBreak)
    #expect(request.key == "AXButton Reset")
    #expect(script.resolved.map(\.retry) == [.live])
    #expect(script.since == [1.5])
    #expect(script.began == [Self.press("Reset")])
    #expect(ledger.controls["AXButton Reset"]?.attempts == 1)
    #expect(ledger.skips.isEmpty)
  }

  @Test func aSkippedPickIsTakenBackAndTheNextOneIsWaitedForFromTheSkip() throws {
    let script = Script([Self.press("Gone"), Self.press("Reset")])
    script.failures["Gone"] = ResolutionFailure.missing("Gone")
    var ledger = SkipLedger()
    ledger.beginRun()
    script.clock.advance(3)
    let started = script.clock.now
    let slot = try live(script, ledger: &ledger, slot: 9, since: 1.5)
    #expect(slot.action == Self.press("Reset"))
    #expect(script.began == [Self.press("Gone"), Self.press("Reset")])
    #expect(script.skipped.count == 1)
    #expect(script.skipped[0].0.slot == 9)
    #expect(script.skipped[0].0.kind == "press")
    #expect(script.skipped[0].1 == ResolutionFailure.missing("Gone"))
    #expect(ledger.skips.count == 1)
    #expect(ledger.skips[0].diagnostics == "diagnostics-1.json")
    #expect(script.since.count == 2)
    #expect(script.since[0] == 1.5)
    #expect(near(script.since[1], started + 0.2))
    #expect(near(slot.skipSeconds, 0.2))
    #expect(script.resolved.map(\.retry) == [.live, .live])
  }

  @Test func aSkipWithoutADiagnosticsFileRecordsNone() throws {
    let script = Script([Self.press("Gone"), Self.press("Reset")])
    script.failures["Gone"] = ResolutionFailure.missing("Gone")
    script.diagnostics = nil
    var ledger = SkipLedger()
    ledger.beginRun()
    _ = try live(script, ledger: &ledger)
    #expect(ledger.skips[0].diagnostics == nil)
  }

  @Test func skipTimeAddsUpAcrossSkippedPicks() throws {
    let script = Script([Self.press("A"), Self.press("B"), Self.press("C")])
    script.failures["A"] = ResolutionFailure.missing("A")
    script.failures["B"] = ResolutionFailure.missing("B")
    script.skipCost = 0.25
    var ledger = SkipLedger()
    ledger.beginRun()
    let slot = try live(script, ledger: &ledger)
    #expect(near(slot.skipSeconds, 0.5))
    #expect(ledger.skips.count == 2)
  }

  @Test func aFailureTheLedgerRefusesToSkipIsTerminalAndKeepsItsAction() {
    let script = Script([Self.press("A"), Self.press("B"), Self.press("C")])
    for name in ["A", "B", "C"] { script.failures[name] = ResolutionFailure.missing(name) }
    var ledger = SkipLedger()
    ledger.beginRun()
    let failure = slotFailure { try live(script, ledger: &ledger) }
    #expect(failure?.reason == .consecutiveBudget)
    #expect(failure?.action == Self.press("C"))
    #expect(failure?.request.label == "C")
    #expect((failure?.underlying as? ResolutionFailure) == ResolutionFailure.missing("C"))
    #expect(near(failure?.skipSeconds, 0.4))
    #expect(script.skipped.count == 2)
    #expect(script.began.count == 3)
    #expect(ResolutionFindings.signature(for: failure!) == "Control not found: C")
  }

  @Test func disabledSkippingFailsFast() {
    let script = Script([Self.press("A")])
    script.failures["A"] = ResolutionFailure.missing("A")
    var ledger = SkipLedger(policy: SkipPolicy(maximumPerRun: 0))
    let failure = slotFailure { try live(script, ledger: &ledger) }
    #expect(failure?.reason == .disabled)
    #expect(script.skipped.isEmpty)
  }

  @Test func anUnreadableTreeIsNeverSkippedAndNeverTouchesTheLedger() {
    let script = Script([Self.press("A")])
    script.failures["A"] = ResolutionFailure(kind: .missing(.unreadable), label: "A")
    var ledger = SkipLedger()
    let failure = slotFailure { try live(script, ledger: &ledger) }
    #expect(failure?.reason == .notSkippable)
    #expect(ledger.controls.isEmpty)
    #expect(script.skipped.isEmpty)
  }

  @Test func anyOtherErrorFromTheResolverIsTerminal() {
    let script = Script([Self.press("A")])
    script.failures["A"] = Missing()
    var ledger = SkipLedger()
    let failure = slotFailure { try live(script, ledger: &ledger) }
    #expect(failure?.reason == .notSkippable)
    #expect(failure?.underlying is Missing)
    #expect(ledger.controls.isEmpty)
  }

  @Test func aPickThatNeedsNoControlResolvesNothingAndResetsTheRun() throws {
    let script = Script([Self.press("Gone"), Self.press("Also gone"), Self.shortcut])
    script.failures["Gone"] = ResolutionFailure.missing("Gone")
    script.failures["Also gone"] = ResolutionFailure.missing("Also gone")
    var ledger = SkipLedger()
    ledger.beginRun()
    let slot = try live(script, ledger: &ledger)
    #expect(slot.action == Self.shortcut)
    #expect(slot.request == nil)
    #expect(slot.target == nil)
    #expect(script.resolved.count == 2)

    let next = Script([Self.press("A"), Self.press("B")])
    next.failures["A"] = ResolutionFailure.missing("A")
    let after = try live(next, ledger: &ledger)
    #expect(after.action == Self.press("B"))
    #expect(ledger.skips.count == 3)
  }

  @Test func errorsFromTheCallersOwnStepsPropagateUnchanged() {
    struct Refused: Error {}
    var ledger = SkipLedger()
    let fromBegin = thrown {
      try resolveLiveSlot(
        slot: 1, since: 0, ledger: &ledger, clock: FakeClock(),
        pick: { _ in Self.press("A") }, begin: { _ in throw Refused() },
        resolve: { _, _ in "x" }, didSkip: { _, _ in nil })
    }
    #expect(fromBegin is Refused)
    let fromSkip = thrown {
      try resolveLiveSlot(
        slot: 1, since: 0, ledger: &ledger, clock: FakeClock(),
        pick: { _ in Self.press("A") }, begin: { _ in },
        resolve: { _, _ -> String in throw ResolutionFailure.missing("A") },
        didSkip: { _, _ in throw Refused() })
    }
    #expect(fromSkip is Refused)
  }

  @Test func aRecordedActionResolvesStrictlyWithTheRecordedRetry() throws {
    let script = Script([])
    let slot = try resolveRecordedSlot(
      action: Self.press("Reset"), begin: script.begin, resolve: script.resolve)
    #expect(slot.target == "element Reset")
    let request = try #require(slot.request)
    #expect(!request.allowVisibleTieBreak)
    #expect(script.resolved.map(\.retry) == [.recorded])
    #expect(script.began == [Self.press("Reset")])
  }

  @Test func aRecordedActionThatNeedsNoControlResolvesNothing() throws {
    let script = Script([])
    let slot = try resolveRecordedSlot(
      action: Self.shortcut, begin: script.begin, resolve: script.resolve)
    #expect(slot.request == nil)
    #expect(slot.target == nil)
    #expect(script.resolved.isEmpty)
    #expect(script.began == [Self.shortcut])
  }

  @Test func aRecordedFailureIsAlwaysTerminal() {
    let script = Script([])
    script.failures["Gone"] = ResolutionFailure.missing("Gone")
    let failure = slotFailure {
      try resolveRecordedSlot(
        action: Self.press("Gone"), begin: script.begin, resolve: script.resolve)
    }
    #expect(failure?.reason == .recordedAction)
    #expect(failure?.action == Self.press("Gone"))
    #expect(failure?.skipSeconds == 0)
    #expect(script.began == [Self.press("Gone")])
    #expect(script.skipped.isEmpty)
  }
}
