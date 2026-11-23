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

public enum MousePreparation {
  public static let notificationCenterBundleIdentifier = "com.apple.notificationcenterui"

  public static func closeAction(in actions: [String]) -> String? {
    actions.first { $0.split(separator: "\n", maxSplits: 1).first == "Name:Close" }
  }

  public struct Hit: Equatable, Sendable {
    public var routing: MouseRouting
    public var process: Int32
    public var bundleIdentifier: String?

    public init(routing: MouseRouting, process: Int32, bundleIdentifier: String? = nil) {
      self.routing = routing
      self.process = process
      self.bundleIdentifier = bundleIdentifier
    }
  }

  public struct Outcome: Equatable, Sendable {
    public var hit: Hit
    public var notificationDismissals: Int
    public var milliseconds: Double

    public var recovered: Bool { hit.routing == .target }
  }

  public static func run(
    clock: some ResolutionClock, allowNotificationDismissal: Bool,
    timeout: TimeInterval = 1.5, notificationSettleSeconds: TimeInterval = 5,
    pollInterval: TimeInterval = 0.02, hitTest: () -> Hit,
    dismissNotification: (Int32) throws -> Bool, checkpoint: () throws -> Void
  ) throws -> Outcome {
    precondition(timeout > 0 && notificationSettleSeconds > 0 && pollInterval > 0)
    let start = clock.now
    var deadline = start + timeout
    var attemptedDismissal = false
    var dismissals = 0
    var hit: Hit
    var finished = false
    repeat {
      try checkpoint()
      hit = hitTest()
      finished = hit.routing == .target || !hit.routing.mayResolve || clock.now >= deadline
      if !finished {
        if allowNotificationDismissal && !attemptedDismissal && hit.routing == .otherProcess,
          hit.bundleIdentifier == notificationCenterBundleIdentifier
        {
          attemptedDismissal = true
          if try dismissNotification(hit.process) {
            dismissals = 1
            deadline = clock.now + notificationSettleSeconds
          }
        }
        let remaining = deadline - clock.now
        if remaining > 0 { clock.sleep(min(pollInterval, remaining)) }
      }
    } while !finished
    return Outcome(
      hit: hit, notificationDismissals: dismissals, milliseconds: (clock.now - start) * 1000)
  }
}
