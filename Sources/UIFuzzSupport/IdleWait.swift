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

/// A run whose budget is spent stops waiting; that is not a failure.
public struct IdleBudget: Equatable, Sendable {
  public static let runSeconds: TimeInterval = 8

  public let limit: TimeInterval
  public private(set) var spent: TimeInterval = 0
  public private(set) var waits = 0
  public private(set) var timeouts = 0
  public private(set) var skipped = 0

  public init(limit: TimeInterval = IdleBudget.runSeconds) {
    self.limit = limit
  }

  public var remaining: TimeInterval { max(0, limit - spent) }

  mutating func record(seconds: TimeInterval, timedOut: Bool) {
    spent += seconds
    waits += 1
    if timedOut { timeouts += 1 }
  }

  mutating func recordSkip() {
    skipped += 1
  }
}

public struct IdleWaitResult: Equatable, Sendable {
  public var seconds: TimeInterval
  public var timedOut: Bool
  /// The run's budget was already spent, so nothing was read or waited for.
  public var skipped: Bool
  public var openWork: [String: Int]
}

public enum IdleWait {
  public static let pollInterval: TimeInterval = 0.025
  public static let beforeDiscovery: TimeInterval = 1.0

  /// `tail` and `budget` belong to one run, so a poll parses only the bytes the file gained since
  /// the previous poll of any wait. `since` and `clock` must use the app's uptime clock.
  public static func run(
    since: TimeInterval, quiescence: TimeInterval, clock: some ResolutionClock,
    tail: inout TelemetryTail, budget: inout IdleBudget, read: (_ offset: Int) -> Data
  ) -> IdleWaitResult {
    let start = clock.now
    let allowance = min(beforeDiscovery, budget.remaining)
    guard allowance > 0 else {
      budget.recordSkip()
      return IdleWaitResult(seconds: 0, timedOut: false, skipped: true, openWork: [:])
    }
    let deadline = start + allowance
    func poll() -> (summary: TelemetrySummary, idle: Bool) {
      let summary = tail.refresh(read: read)
      return (summary, summary.isIdle(since: since, now: clock.now, quiescence: quiescence))
    }
    var (summary, idle) = poll()
    while !idle && clock.now < deadline {
      clock.sleep(min(pollInterval, deadline - clock.now))
      (summary, idle) = poll()
    }
    let seconds = clock.now - start
    budget.record(seconds: seconds, timedOut: !idle)
    return IdleWaitResult(
      seconds: seconds, timedOut: !idle, skipped: false, openWork: summary.openWorkKinds)
  }
}
