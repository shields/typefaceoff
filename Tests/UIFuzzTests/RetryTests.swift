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

@Suite struct RetryTests {
  struct Stop: Error, Equatable {}

  let world = FakeWorld()
  let clock = FakeClock()

  var control: FakeNode { world.node("AXButton", name: "Size") }

  func script(
    _ retry: ResolutionRetry, foundOn: Int?, idle: Bool = false,
    checkpoint: () throws -> Void = {}
  ) throws -> (
    result: Resolution<FakeNode>, attempts: Int, times: [TimeInterval], idle: [TimeInterval]
  ) {
    var times: [TimeInterval] = []
    var idleCalls: [TimeInterval] = []
    let found = control
    let (result, attempts) = try retry.run(
      clock: clock,
      idle: {
        idleCalls.append($0)
        return idle
      }, checkpoint: checkpoint,
      attempt: {
        times.append(clock.now)
        return times.count == foundOn ? .found(found, .path) : .missing(.noMatch)
      })
    return (result, attempts, times, idleCalls)
  }

  func expectTimes(_ actual: [TimeInterval], _ expected: [TimeInterval]) {
    #expect(actual.count == expected.count)
    for (left, right) in zip(actual, expected) { #expect(abs(left - right) < 1e-4) }
  }

  @Test func immediateSuccessNeitherSleepsNorAsksAboutIdleness() throws {
    let run = try script(.recorded, foundOn: 1)
    #expect(run.attempts == 1)
    #expect(run.result.step == .path)
    #expect(clock.sleeps.isEmpty)
    #expect(run.idle.isEmpty)
  }

  @Test func succeedsOnTheThirdAttempt() throws {
    let run = try script(.recorded, foundOn: 3)
    #expect(run.attempts == 3)
    #expect(run.result.node != nil)
    expectTimes(run.times, [0, 0.25, 0.5])
    expectTimes(run.idle, [0, 0.25])
  }

  @Test func idleAppsAreProbedSoonerThanBusyOnes() throws {
    let run = try script(.recorded, foundOn: 3, idle: true)
    expectTimes(run.times, [0, 0.1, 0.2])
    #expect(clock.sleeps.allSatisfy { $0 <= ResolutionRetry.wakeInterval + 1e-9 })
  }

  @Test func maximumAttemptsStopsTheLoopWithTheLastOutcome() throws {
    let retry = ResolutionRetry(timeoutSeconds: 100, maximumAttempts: 3)
    let run = try script(retry, foundOn: nil)
    #expect(run.attempts == 3)
    #expect(run.times.count == 3)
    if case .missing(.noMatch) = run.result {} else { Issue.record("Expected the last miss") }
  }

  @Test func aFinalAttemptRunsAtTheDeadline() throws {
    let retry = ResolutionRetry(timeoutSeconds: 1, maximumAttempts: .max)
    let run = try script(retry, foundOn: nil)
    expectTimes(run.times, [0, 0.25, 0.5, 0.75, 1])
    #expect(run.attempts == 5)
  }

  @Test func aSleepNeverOvershootsTheDeadline() throws {
    let retry = ResolutionRetry(timeoutSeconds: 0.12, maximumAttempts: .max)
    let run = try script(retry, foundOn: nil)
    #expect(run.attempts == 2)
    #expect(clock.now < 0.12 + 1e-4)
    expectTimes(run.times, [0, 0.12])
  }

  @Test func aSlowAttemptGoesStraightToTheNextOne() throws {
    let retry = ResolutionRetry(timeoutSeconds: 1, maximumAttempts: 2)
    var times: [TimeInterval] = []
    _ = try retry.run(
      clock: clock, idle: { _ in true }, checkpoint: {},
      attempt: {
        times.append(clock.now)
        clock.advance(0.4)
        return .missing(.noMatch) as Resolution<FakeNode>
      })
    #expect(clock.sleeps.isEmpty)
    expectTimes(times, [0, 0.4])
  }

  @Test func aThrowingCheckpointStopsBeforeTheFirstAttempt() {
    var attempts = 0
    #expect(throws: Stop()) {
      try ResolutionRetry.recorded.run(
        clock: clock, idle: { _ in false }, checkpoint: { throw Stop() },
        attempt: {
          attempts += 1
          return .missing(.noMatch) as Resolution<FakeNode>
        })
    }
    #expect(attempts == 0)
  }

  @Test func aThrowingCheckpointStopsALaterAttempt() {
    var checkpoints = 0
    var attempts = 0
    #expect(throws: Stop()) {
      try ResolutionRetry.recorded.run(
        clock: clock, idle: { _ in false },
        checkpoint: {
          checkpoints += 1
          if checkpoints == 3 { throw Stop() }
        },
        attempt: {
          attempts += 1
          return .missing(.noMatch) as Resolution<FakeNode>
        })
    }
    #expect(attempts == 2)
  }

  @Test func everyAttemptCapturesAFreshTree() throws {
    var captures = 0
    let (result, attempts) = try ResolutionRetry.recorded.run(
      clock: clock, idle: { _ in false }, checkpoint: {},
      attempt: {
        captures += 1
        let root = world.application([world.window(children: captures < 2 ? [] : [control])])
        return world.resolver(root, focused: nil, clock: clock).resolve(
          ResolutionRequest(target: "Size"))
      })
    #expect(captures == 2)
    #expect(attempts == 2)
    #expect(result.step == .firstName)
  }

  @Test func theReadinessProbeAttemptsOnceAndNeverSleeps() throws {
    let run = try script(.once, foundOn: nil)
    #expect(run.attempts == 1)
    #expect(clock.sleeps.isEmpty)
    #expect(run.idle.isEmpty)
    #expect(run.result.node == nil)
  }

  @Test func theBudgetsAreThePlannedOnes() {
    #expect(ResolutionRetry.recorded == ResolutionRetry(timeoutSeconds: 2, maximumAttempts: .max))
    #expect(ResolutionRetry.live == ResolutionRetry(timeoutSeconds: 0.5, maximumAttempts: 3))
    #expect(ResolutionRetry.reveal == ResolutionRetry(timeoutSeconds: 1, maximumAttempts: .max))
    #expect(ResolutionRetry.once == ResolutionRetry(timeoutSeconds: 0.001, maximumAttempts: 1))
    #expect(ResolutionRetry.idleInterval == 0.1)
    #expect(ResolutionRetry.busyInterval == 0.25)
    #expect(ResolutionRetry.wakeInterval == 0.05)
  }

  @Test func liveBudgetGivesUpAfterThreeAttempts() throws {
    let run = try script(.live, foundOn: nil)
    #expect(run.attempts == 3)
    #expect(clock.now <= 0.5 + 1e-4)
  }
}
