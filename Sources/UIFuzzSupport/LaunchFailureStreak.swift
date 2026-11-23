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

public struct LaunchLoopError: Error, LocalizedError, CustomStringConvertible, Equatable {
  public let count: Int
  public let findingFile: String

  public var description: String {
    "The app cannot start: \(count) consecutive executions exited during launch. Finding report: \(findingFile). Check the app build (code signature, missing libraries, a crash at startup) before restarting the campaign."
  }

  public var errorDescription: String? { description }
}

/// Counts consecutive executions in which the app died during launch. That failure does not
/// depend on the trace, so repeating it only fills the artifact directory. A crash after a
/// normal launch is a finding about a trace and resets the count.
public struct LaunchFailureStreak: Sendable {
  public static let defaultThreshold = 5

  public let threshold: Int
  public private(set) var count = 0

  public init(threshold: Int = LaunchFailureStreak.defaultThreshold) {
    precondition(threshold > 0)
    self.threshold = threshold
  }

  public mutating func record(_ report: ExecutionReport, findingFile: String) throws {
    let failed = report.findings.contains {
      $0.kind == .crash && $0.signature == ProcessLiveness.launchTerminationSignature
    }
    count = failed ? count + 1 : 0
    if count >= threshold {
      throw LaunchLoopError(count: count, findingFile: findingFile)
    }
  }
}
