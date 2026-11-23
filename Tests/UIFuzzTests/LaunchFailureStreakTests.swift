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

@Suite struct LaunchFailureStreakTests {
  private func report(_ findings: [ExecutionFinding]) -> ExecutionReport {
    ExecutionReport(
      trace: FuzzTrace(seed: 1, actions: []), startedAt: Date(timeIntervalSince1970: 0),
      durationMilliseconds: 1, actionMilliseconds: [], findings: findings)
  }

  private var launchFailure: ExecutionReport {
    report([
      ProcessLiveness.unexpectedExitFinding(
        phase: .launch, actionsDispatched: 0, lastAction: nil, secondsSinceLastAction: nil,
        secondsSinceHeartbeat: nil)
    ])
  }

  @Test func defaultThresholdIsFive() {
    #expect(LaunchFailureStreak().threshold == 5)
    #expect(LaunchFailureStreak.defaultThreshold == 5)
  }

  @Test func consecutiveLaunchFailuresStopAtTheThreshold() throws {
    var streak = LaunchFailureStreak(threshold: 3)
    try streak.record(launchFailure, findingFile: "a.json")
    try streak.record(launchFailure, findingFile: "b.json")
    #expect(streak.count == 2)
    #expect(throws: LaunchLoopError(count: 3, findingFile: "c.json")) {
      try streak.record(launchFailure, findingFile: "c.json")
    }
  }

  @Test func aCleanExecutionResetsTheStreak() throws {
    var streak = LaunchFailureStreak(threshold: 2)
    try streak.record(launchFailure, findingFile: "a.json")
    try streak.record(report([]), findingFile: "b.json")
    #expect(streak.count == 0)
    try streak.record(launchFailure, findingFile: "c.json")
    #expect(streak.count == 1)
  }

  @Test func aCrashAfterALaunchThatWorkedResetsTheStreak() throws {
    var streak = LaunchFailureStreak(threshold: 2)
    try streak.record(launchFailure, findingFile: "a.json")
    let crash = report([
      ProcessLiveness.unexpectedExitFinding(
        phase: .duringAction, actionsDispatched: 4, lastAction: "click",
        secondsSinceLastAction: 0.1, secondsSinceHeartbeat: 0.2)
    ])
    for _ in 0..<10 { try streak.record(crash, findingFile: "crash.json") }
    #expect(streak.count == 0)
  }

  @Test func otherFindingsDoNotCount() throws {
    var streak = LaunchFailureStreak(threshold: 1)
    let others = [
      ExecutionFinding(kind: .automation, signature: "launch-termination", detail: ""),
      ExecutionFinding(kind: .hang, signature: "launch-termination", detail: ""),
      ExecutionFinding(kind: .crash, signature: "unexpected-termination", detail: ""),
      ExecutionFinding(kind: .unavailable, signature: "desktop-session", detail: ""),
    ]
    for finding in others { try streak.record(report([finding]), findingFile: "x.json") }
    #expect(streak.count == 0)
  }

  @Test func aLaunchFailureAmongOtherFindingsCounts() {
    var streak = LaunchFailureStreak(threshold: 1)
    let mixed = report(
      [ExecutionFinding(kind: .automation, signature: "missing-telemetry", detail: "")]
        + launchFailure.findings)
    #expect(throws: LaunchLoopError.self) { try streak.record(mixed, findingFile: "m.json") }
  }

  @Test func errorNamesTheStreakTheFileAndTheProblem() {
    let error = LaunchLoopError(count: 5, findingFile: "/tmp/findings/crash/00000007-ab.json")
    #expect(
      error.description
        == "The app cannot start: 5 consecutive executions exited during launch. Finding report: /tmp/findings/crash/00000007-ab.json. Check the app build (code signature, missing libraries, a crash at startup) before restarting the campaign."
    )
    #expect(error.errorDescription == error.description)
    #expect(error.localizedDescription == error.description)
  }
}
