import Foundation

public struct LaunchLoopError: Error, LocalizedError, CustomStringConvertible, Equatable {
  public let count: Int
  public let lastFindingFile: String

  public var description: String {
    "The app cannot start: \(count) consecutive executions exited during launch. Last finding: \(lastFindingFile). Check the app build (code signature, missing libraries, a crash at startup) before restarting the campaign."
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

  /// The caller has already written `findingFile`, the evidence for `report`.
  public mutating func record(_ report: ExecutionReport, findingFile: String) throws {
    let failed = report.findings.contains {
      $0.kind == .crash && $0.signature == ProcessLiveness.launchTerminationSignature
    }
    count = failed ? count + 1 : 0
    if count >= threshold {
      throw LaunchLoopError(count: count, lastFindingFile: findingFile)
    }
  }
}
