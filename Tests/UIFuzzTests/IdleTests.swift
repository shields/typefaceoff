import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct IdleTests {
  typealias Lines = TelemetryLines

  final class ScriptedFile {
    var bytes = Data()
    private(set) var offsets: [Int] = []
    var onRead: (ScriptedFile, Int) -> Void = { _, _ in }

    init(_ text: String = "") { append(text) }

    func append(_ text: String) { bytes.append(Data(text.utf8)) }

    func read(_ offset: Int) -> Data {
      offsets.append(offset)
      onRead(self, offsets.count)
      return Data(bytes.dropFirst(offset))
    }
  }

  let clock = FakeClock()

  /// Uptime 10, in the middle of a run whose previous action returned at uptime 9.
  init() { clock.advance(10) }

  func summary(
    events: Int = 10, heartbeat: TimeInterval? = 10, activity: TimeInterval? = 9.5,
    pending: Int = 0
  ) -> TelemetrySummary {
    var summary = TelemetrySummary()
    summary.events = events
    summary.lastHeartbeat = heartbeat
    summary.lastActivity = activity
    for index in 0..<pending { summary.openWork["span-\(index)"] = "ranking" }
    return summary
  }

  func idle(
    _ summary: TelemetrySummary, since: TimeInterval = 9, now: TimeInterval = 10,
    quiescence: TimeInterval = 0.5
  ) -> Bool {
    summary.isIdle(since: since, now: now, quiescence: quiescence)
  }

  @Test func aQuietAppThatHasHeardFromEveryConditionIsIdle() {
    #expect(idle(summary()))
  }

  @Test func anEmptyOrTornReadIsNeverIdle() {
    #expect(!idle(summary(events: 0)))
    #expect(!idle(TelemetrySummary()))
  }

  @Test func openWorkIsNeverIdle() {
    #expect(!idle(summary(pending: 1)))
    #expect(!idle(summary(pending: 3)))
  }

  @Test func theMainThreadMustHaveRunSinceTheWaitBegan() {
    #expect(!idle(summary(heartbeat: nil)))
    #expect(!idle(summary(heartbeat: 8.75)))
    #expect(idle(summary(heartbeat: 9)))
    #expect(idle(summary(heartbeat: 9.25)))
  }

  @Test func theQuiescenceFloorMustHaveElapsedSinceTheWaitBegan() {
    #expect(!idle(summary(activity: nil), now: 9.25))
    #expect(idle(summary(activity: nil), now: 9.5))
    #expect(idle(summary(activity: nil), now: 9.75))
  }

  @Test func theLastActivityMustBeHalfTheFloorOld() {
    #expect(!idle(summary(activity: 9.8125)))
    #expect(idle(summary(activity: 9.75)))
    #expect(idle(summary(activity: 9.5)))
    #expect(!idle(summary(activity: 10)))
  }

  @Test func anAppWithoutActivityIsIdleOnceTheFloorHasElapsed() {
    #expect(idle(summary(activity: nil)))
  }

  @Test func aZeroFloorNeedsOnlyOpenSpansAndAHeartbeat() {
    #expect(idle(summary(activity: nil), now: 9, quiescence: 0))
    #expect(!idle(summary(heartbeat: 8.75, activity: nil), now: 9, quiescence: 0))
  }

  @Test func scriptedTelemetryDecidesIdleness() {
    let busy = TelemetrySummary.parse(
      Lines.text(
        Lines.line("launch", at: 1), Lines.line("heartbeat", at: 9.5),
        Lines.begin("a", "ranking", at: 9.75), Lines.line("heartbeat", at: 10)))
    #expect(!idle(busy))
    let settled = TelemetrySummary.parse(
      Lines.text(
        Lines.line("launch", at: 1), Lines.begin("a", "ranking", at: 9.25),
        Lines.end("a", at: 9.5), Lines.line("heartbeat", at: 10)))
    #expect(idle(settled))
    let recent = TelemetrySummary.parse(
      Lines.text(
        Lines.line("launch", at: 1), Lines.line("snapshot", at: 9.875),
        Lines.line("heartbeat", at: 10)))
    #expect(!idle(recent))
  }

  @Test func theBudgetStartsFullAndIsAnEightSecondRunCap() {
    let budget = IdleBudget()
    #expect(budget.limit == 8)
    #expect(IdleBudget.runSeconds == 8)
    #expect(budget.remaining == 8)
    #expect(budget.spent == 0)
    #expect(budget.waits == 0)
    #expect(budget.timeouts == 0)
    #expect(budget.skipped == 0)
    #expect(IdleBudget(limit: 2).remaining == 2)
  }

  @Test func theBudgetRecordsWaitsTimeoutsAndSkips() {
    var budget = IdleBudget(limit: 2)
    budget.record(seconds: 0.5, timedOut: false)
    budget.record(seconds: 1, timedOut: true)
    budget.recordSkip()
    #expect(budget.spent == 1.5)
    #expect(budget.remaining == 0.5)
    #expect(budget.waits == 2)
    #expect(budget.timeouts == 1)
    #expect(budget.skipped == 1)
    budget.record(seconds: 5, timedOut: true)
    #expect(budget.remaining == 0)
  }

  @Test func thePlannedTimingConstants() {
    #expect(IdleWait.pollInterval == 0.025)
    #expect(IdleWait.beforeDiscovery == 1)
  }

  @Test func anAlreadyIdleAppEndsTheWaitAtOnce() {
    let file = ScriptedFile(
      Lines.text(
        Lines.line("launch", at: 1), Lines.line("heartbeat", at: 9.5),
        Lines.line("heartbeat", at: 10)))
    var tail = TelemetryTail()
    var budget = IdleBudget()
    let result = IdleWait.run(
      since: 9, quiescence: 0.5, clock: clock, tail: &tail, budget: &budget, read: file.read)
    #expect(result == IdleWaitResult(seconds: 0, timedOut: false, skipped: false, openWork: [:]))
    #expect(clock.sleeps.isEmpty)
    #expect(file.offsets == [0])
    #expect(budget.waits == 1)
    #expect(budget.spent == 0)
    #expect(budget.timeouts == 0)
  }

  @Test func idlenessArrivesAfterScriptedPolls() {
    let file = ScriptedFile(
      Lines.text(
        Lines.line("launch", at: 1), Lines.line("heartbeat", at: 9.5),
        Lines.begin("a", "ranking", at: 9.75)))
    let spanEnds = 3
    let clock = clock
    file.onRead = { file, count in
      if count == spanEnds {
        file.append(
          Lines.text(Lines.end("a", at: clock.now), Lines.line("heartbeat", at: clock.now)))
      }
    }
    var tail = TelemetryTail()
    var budget = IdleBudget()
    let result = IdleWait.run(
      since: 9, quiescence: 0.28, clock: clock, tail: &tail, budget: &budget, read: file.read)
    #expect(!result.timedOut)
    #expect(!result.skipped)
    #expect(result.openWork.isEmpty)
    #expect(abs(result.seconds - 0.2) < 1e-6)
    #expect(clock.sleeps.count == 8)
    #expect(clock.sleeps.allSatisfy { $0 == IdleWait.pollInterval })
    #expect(file.offsets.count == 9)
    #expect(budget.waits == 1)
    #expect(abs(budget.spent - 0.2) < 1e-6)
    #expect(budget.timeouts == 0)
  }

  @Test func pollsParseOnlyTheBytesTheFileGained() {
    let file = ScriptedFile(
      Lines.text(Lines.line("launch", at: 1), Lines.begin("a", "ranking", at: 9.75)))
    let initialSize = file.bytes.count
    let clock = clock
    file.onRead = { file, count in
      if count == 2 {
        file.append(Lines.line("heartbeat", at: clock.now))
      } else if count == 3 {
        file.append("\n")
      } else if count == 4 {
        file.append(Lines.text(Lines.end("a", at: clock.now)))
      }
    }
    var tail = TelemetryTail()
    var budget = IdleBudget()
    _ = IdleWait.run(
      since: 9, quiescence: 0.28, clock: clock, tail: &tail, budget: &budget, read: file.read)
    #expect(file.offsets.filter { $0 == 0 }.count == 1)
    #expect(file.offsets == file.offsets.sorted())
    #expect(file.offsets[1] == initialSize)
    #expect(tail.offset == file.bytes.count)
    #expect(tail.summary.events == 4)
    #expect(tail.summary.pendingWork == 0)
  }

  @Test func aWaitTimesOutAtTheCapAndReportsWhatIsStillOpen() {
    let file = ScriptedFile(
      Lines.text(
        Lines.line("heartbeat", at: 9.5), Lines.begin("a", "ranking", at: 9.75),
        Lines.begin("b", "ranking", at: 9.75), Lines.begin("c", "feature-preview", at: 9.75)))
    var tail = TelemetryTail()
    var budget = IdleBudget()
    let result = IdleWait.run(
      since: 9, quiescence: 0.5, clock: clock, tail: &tail, budget: &budget, read: file.read)
    #expect(result.timedOut)
    #expect(!result.skipped)
    #expect(result.openWork == ["ranking": 2, "feature-preview": 1])
    #expect(abs(result.seconds - IdleWait.beforeDiscovery) < 1e-6)
    #expect(clock.sleeps.count == 40)
    #expect(budget.timeouts == 1)
    #expect(budget.waits == 1)
    #expect(abs(budget.spent - 1) < 1e-6)
  }

  @Test func aWaitWithoutTelemetryTimesOut() {
    let file = ScriptedFile()
    var tail = TelemetryTail()
    var budget = IdleBudget()
    let result = IdleWait.run(
      since: 9, quiescence: 0.5, clock: clock, tail: &tail, budget: &budget, read: file.read)
    #expect(result.timedOut)
    #expect(result.openWork.isEmpty)
  }

  @Test func theRunCapEndsWaitingWithoutFailing() {
    let file = ScriptedFile(
      Lines.text(Lines.line("heartbeat", at: 9.5), Lines.begin("a", "ranking", at: 9.75)))
    var tail = TelemetryTail()
    var budget = IdleBudget(limit: 1.5)
    var results: [IdleWaitResult] = []
    for _ in 0..<3 {
      results.append(
        IdleWait.run(
          since: 9, quiescence: 0.5, clock: clock, tail: &tail, budget: &budget, read: file.read))
    }
    #expect(results.map(\.timedOut) == [true, true, false])
    #expect(results.map(\.skipped) == [false, false, true])
    #expect(abs(results[0].seconds - 1) < 1e-6)
    #expect(abs(results[1].seconds - 0.5) < 1e-6)
    #expect(results[2].seconds == 0)
    #expect(results[2].openWork.isEmpty)
    #expect(budget.remaining == 0)
    #expect(budget.waits == 2)
    #expect(budget.timeouts == 2)
    #expect(budget.skipped == 1)
  }

  @Test func aSpentBudgetNeitherReadsNorSleeps() {
    let file = ScriptedFile(Lines.text(Lines.line("heartbeat", at: 10)))
    var tail = TelemetryTail()
    var budget = IdleBudget(limit: 0)
    let result = IdleWait.run(
      since: 9, quiescence: 0.5, clock: clock, tail: &tail, budget: &budget, read: file.read)
    #expect(result == IdleWaitResult(seconds: 0, timedOut: false, skipped: true, openWork: [:]))
    #expect(file.offsets.isEmpty)
    #expect(clock.sleeps.isEmpty)
    #expect(budget.skipped == 1)
    #expect(budget.waits == 0)
  }

  @Test func idleWaitsShareOneBudget() {
    let file = ScriptedFile(
      Lines.text(Lines.line("heartbeat", at: 9.5), Lines.line("heartbeat", at: 10)))
    var tail = TelemetryTail()
    var budget = IdleBudget()
    for _ in 0..<2 {
      let result = IdleWait.run(
        since: 9, quiescence: 0.5, clock: clock, tail: &tail, budget: &budget, read: file.read)
      #expect(!result.timedOut)
    }
    #expect(budget.waits == 2)
    #expect(budget.spent == 0)
    #expect(file.offsets == [0, file.bytes.count])
  }

  @Test func waitingOnARealFileReadsItThroughTheFileReader() throws {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "telemetry-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(
      Lines.text(Lines.line("launch", at: 1), Lines.line("heartbeat", at: 10)).utf8
    ).write(to: url)
    var tail = TelemetryTail()
    var budget = IdleBudget()
    let result = IdleWait.run(
      since: 9, quiescence: 0.5, clock: clock, tail: &tail, budget: &budget,
      read: { TelemetryFile.bytes(at: url, from: $0) })
    #expect(!result.timedOut)
    #expect(tail.summary.events == 2)
  }
}
