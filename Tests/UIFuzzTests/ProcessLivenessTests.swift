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

@Suite struct ProcessLivenessTests {
  private func spawnSleep() throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["60"]
    try process.run()
    return process
  }

  @Test func realProcessIsAliveUntilItExits() throws {
    let process = try spawnSleep()
    defer { if process.isRunning { process.terminate() } }
    #expect(ProcessLiveness.isAlive(process.processIdentifier))
    #expect(
      !ProcessLiveness.waitForExit(process.processIdentifier, timeout: 0.05),
      "a live process must time out")

    process.terminate()
    #expect(ProcessLiveness.waitForExit(process.processIdentifier, timeout: 5))
    #expect(!ProcessLiveness.isAlive(process.processIdentifier))
  }

  @Test func processOwnedBySomeoneElseIsAlive() {
    #expect(ProcessLiveness.isAlive(1))
  }

  @Test func nonPositiveIdentifiersAreNotProcesses() {
    #expect(!ProcessLiveness.isAlive(0))
    #expect(!ProcessLiveness.isAlive(-1))
  }

  @Test func waitPollsUntilTheProcessIsGone() {
    var now = 100.0
    var polls = 0
    var sleeps: [TimeInterval] = []
    let exited = ProcessLiveness.waitForExit(
      42, timeout: 1, pollInterval: 0.25,
      clock: { now },
      sleep: {
        sleeps.append($0)
        now += $0
      },
      isAlive: { pid in
        #expect(pid == 42)
        polls += 1
        return polls < 4
      })
    #expect(exited)
    #expect(sleeps == [0.25, 0.25, 0.25])
    #expect(now == 100.75)
  }

  @Test func waitClampsItsLastSleepToTheDeadline() {
    var now = 0.0
    var sleeps: [TimeInterval] = []
    let exited = ProcessLiveness.waitForExit(
      42, timeout: 0.625, pollInterval: 0.25,
      clock: { now },
      sleep: {
        sleeps.append($0)
        now += $0
      },
      isAlive: { _ in true })
    #expect(!exited)
    #expect(sleeps == [0.25, 0.25, 0.125])
  }

  @Test func waitReportsAnAlreadyExitedProcessWithoutSleeping() {
    let exited = ProcessLiveness.waitForExit(
      42, timeout: 0,
      clock: { 0 },
      sleep: { _ in Issue.record("must not sleep") },
      isAlive: { _ in false })
    #expect(exited)
  }

  @Test func unexpectedExitFindingsDescribeWhereTheAppWasLost() {
    let launch = ProcessLiveness.unexpectedExitFinding(
      phase: .launch, actionsDispatched: 0, lastAction: nil, secondsSinceLastAction: nil,
      secondsSinceHeartbeat: nil)
    #expect(launch.kind == .crash)
    #expect(launch.signature == "launch-termination")
    #expect(launch.detail.contains("during launch"))
    #expect(launch.detail.contains("never emitted a main-thread heartbeat"))

    let between = ProcessLiveness.unexpectedExitFinding(
      phase: .beforeAction, actionsDispatched: 3, lastAction: "press",
      secondsSinceLastAction: 1.234, secondsSinceHeartbeat: 0.056)
    #expect(between.signature == "unexpected-termination")
    #expect(between.detail.contains("before action 4 was dispatched, after 3 actions"))
    #expect(between.detail.contains("Action 3 (press) started 1.23 s before"))
    #expect(between.detail.contains("heartbeat was 0.06 s earlier"))

    let during = ProcessLiveness.unexpectedExitFinding(
      phase: .duringAction, actionsDispatched: 2, lastAction: "click",
      secondsSinceLastAction: 0.5, secondsSinceHeartbeat: 0.5, note: "Driver error: gone")
    #expect(during.signature == "unexpected-termination")
    #expect(during.detail.contains("while the driver was performing an action"))
    #expect(during.detail.hasSuffix("Driver error: gone"))

    let after = ProcessLiveness.unexpectedExitFinding(
      phase: .afterActions, actionsDispatched: 5, lastAction: "key",
      secondsSinceLastAction: 2, secondsSinceHeartbeat: 2)
    #expect(after.detail.contains("after 5 dispatched actions, before the driver requested"))
  }
}
