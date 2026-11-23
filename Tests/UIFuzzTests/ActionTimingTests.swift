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

import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct ActionTimingTests {
  typealias Lines = TelemetryLines

  func attempt(start: Double = 1, end: Double = 3) -> ActionTiming {
    var timing = ActionTiming(
      execution: "run", index: 0, action: FuzzAction(kind: .press, target: "Apply"), start: start)
    timing.resolutionEnd = start + 0.125
    timing.dispatchStart = start + 0.25
    timing.dispatchReturn = start + 0.5
    timing.endedAt = end
    return timing
  }

  @Test func settlesAfterWorkAndAQuietMainThreadTurn() throws {
    let text = Lines.text(
      Lines.line("heartbeat", at: 0), Lines.begin("a", "ranking", at: 1.25),
      Lines.line("heartbeat", at: 1.5), Lines.end("a", at: 2),
      Lines.line("heartbeat", at: 2.125), Lines.line("heartbeat", at: 2.25),
      Lines.begin("b", "unrelated", at: 2.5), Lines.line("heartbeat", at: 3))
    let timing = try #require(ActionQuiescence.measure([attempt()], telemetry: text).first)
    #expect(timing.quiescentAt == 2.25)
    #expect(timing.endedAt == 2.25)
    #expect(timing.latencyMilliseconds == 1250)
    #expect(timing.result == .settled)
    #expect(timing.pendingAtDispatchReturn == ["ranking": 1])
    #expect(timing.pendingAtSettlement == [:])
    #expect(timing.pendingAtEnd == [:])
    #expect(timing.maximumHeartbeatGap == 0.625)
    #expect(
      try JSONDecoder().decode(ActionTiming.self, from: JSONEncoder().encode(timing)) == timing)
  }

  @Test func nextActionBoundsTheMeasurementAndDoesNotInheritAnEarlierStall() {
    var first = attempt(end: 2)
    first.result = .nextActionStarted
    var second = attempt(start: 2, end: 4)
    second.index = 1
    let timings = ActionQuiescence.measure(
      [first, second],
      telemetry: Lines.text(
        Lines.line("heartbeat", at: 0), Lines.begin("a", "ranking", at: 1.25),
        Lines.line("heartbeat", at: 2.25), Lines.end("a", at: 2.5),
        Lines.line("heartbeat", at: 2.75)))
    #expect(timings[0].result == .nextActionStarted)
    #expect(timings[0].quiescentAt == nil)
    #expect(timings[0].latencyMilliseconds == nil)
    #expect(timings[0].maximumHeartbeatGap == 1)
    #expect(timings[0].pendingAtEnd == ["ranking": 1])
    #expect(timings[1].maximumHeartbeatGap == 0.5)
    #expect(timings[1].pendingAtDispatchReturn == [:])
    #expect(timings[1].quiescentAt == 2.75)
  }

  @Test(arguments: [QuiescenceResult.timeout, .appExited, .nextActionStarted])
  func incompleteActionsKeepTheirReasonAndOngoingGap(reason: QuiescenceResult) {
    var timing = attempt()
    timing.result = reason
    let result = ActionQuiescence.measure(
      [timing],
      telemetry: Lines.text(
        Lines.line("heartbeat", at: 1.5), Lines.begin("a", "specimen-layout", at: 1.75)))[0]
    #expect(result.result == reason)
    #expect(result.maximumHeartbeatGap == 1.5)
    #expect(result.pendingAtDispatchReturn == [:])
    #expect(result.pendingAtSettlement == nil)
    #expect(result.pendingAtEnd == ["specimen-layout": 1])
  }

  @Test func resolutionFailuresAreAttemptsWithoutDispatch() {
    var timing = ActionTiming(execution: "run", index: 2, action: .init(kind: .press), start: 1)
    timing.resolutionEnd = 1.5
    timing.endedAt = 2
    timing.failure = "missing control"
    let result = ActionQuiescence.measure(
      [timing],
      telemetry: Lines.text(
        Lines.line("heartbeat", at: 1.75)))[0]
    #expect(result.result == .settled)
    #expect(result.dispatchStart == nil)
    #expect(result.pendingAtDispatchReturn == nil)
    #expect(result.failure == "missing control")
  }

  @Test func missingAndPartialTelemetryCannotSettle() {
    let timing = ActionTiming(execution: "run", index: 0, action: .init(kind: .pause), start: 1)
    let result = ActionQuiescence.measure([timing], telemetry: "garbage\n{}\n{\"uptime\":")[0]
    #expect(result.result == .timeout)
    #expect(result.quiescentAt == nil)
    #expect(!ActionQuiescence.settled(TelemetrySummary(), since: 0))
  }

  @Test func activityAfterHeartbeatCannotSettleOnAStaleHeartbeat() {
    let text = Lines.text(
      Lines.line("heartbeat", at: 1.625), Lines.line("render", at: 1.875),
      Lines.line("heartbeat", at: 2), Lines.line("heartbeat", at: 2.125))
    #expect(ActionQuiescence.measure([attempt()], telemetry: text)[0].quiescentAt == 2.125)
  }

  @Test func workOpenAtDispatchReturnIsReconstructedFromEventTime() {
    let text = Lines.text(
      Lines.begin("a", "specimen-shaping", at: 1.375), Lines.end("a", at: 1.75),
      Lines.line("heartbeat", at: 2))
    let timing = ActionQuiescence.measure([attempt()], telemetry: text)[0]
    #expect(timing.pendingAtDispatchReturn == ["specimen-shaping": 1])
    #expect(timing.pendingAtSettlement == [:])
  }

  @Test func lastDispatchStillGetsAPendingSnapshotWithoutLaterEvents() {
    let text = Lines.text(Lines.begin("a", "ranking", at: 1.375))
    let timing = ActionQuiescence.measure([attempt()], telemetry: text)[0]
    #expect(timing.pendingAtDispatchReturn == ["ranking": 1])
    #expect(timing.maximumHeartbeatGap == 2)
  }

  @Test func appendPreservesExistingExecutionsAndUsesCompactLines() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "executions.jsonl")
    var timing = attempt()
    timing.result = .settled
    let report = ExecutionReport(
      trace: .init(seed: 42), startedAt: Date(timeIntervalSince1970: 0), durationMilliseconds: 1000,
      actionMilliseconds: [25], metadata: ["run": "run", "final-snapshot": "large"])
    let record = ExecutionRecord(report, timings: [timing])
    try ExecutionJournal.append(record, to: file)
    let first = try Data(contentsOf: file)
    try ExecutionJournal.append(ExecutionRecord(report, timings: []), to: file)
    let combined = try Data(contentsOf: file)
    #expect(combined.starts(with: first))
    let lines = combined.split(separator: 0x0A)
    #expect(lines.count == 2)
    let object = try #require(JSONSerialization.jsonObject(with: Data(lines[0])) as? [String: Any])
    #expect(object["execution"] as? String == "run")
    #expect(object["settled"] as? Int == 1)
    #expect(object["attempted"] as? Int == 1)
    #expect(object["completed"] as? Int == 1)
    #expect(object["metadata"] as? [String: String] == ["run": "run"])
    #expect(ExecutionRecord(report, timings: []).settled == 0)
    var unidentified = report
    unidentified.metadata = [:]
    #expect(ExecutionRecord(unidentified, timings: []).execution.isEmpty)
  }

  @Test func separateOpenWritersAppendWithoutOverwriting() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let first = try DriverLog.open(file)
    let second = try DriverLog.open(file)
    try first.write(contentsOf: Data("one\n".utf8))
    try second.write(contentsOf: Data("two\n".utf8))
    try first.write(contentsOf: Data("three\n".utf8))
    try first.close()
    try second.close()
    #expect(try String(contentsOf: file, encoding: .utf8) == "one\ntwo\nthree\n")
  }
}
