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

public struct SkipPolicy: Equatable, Sendable {
  public var maximumPerRun: Int
  public var maximumConsecutive = 2
  public var maximumPerControlPerRun = 1
  public var persistentConsecutive = 3
  /// Any control whose failures reach this count and this share of its attempts is persistently
  /// missing; a count alone would flag every pooled unnamed role on a long campaign.
  public var persistentFailures = 5
  public var persistentRate = 0.5

  /// A `maximumPerRun` of zero means fail-fast.
  public init(maximumPerRun: Int = 5) {
    self.maximumPerRun = maximumPerRun
  }
}

public enum TerminalReason: Equatable, Sendable {
  case disabled
  case persistent(key: String, consecutive: Int, failures: Int, attempts: Int)
  case repeatedInRun
  case consecutiveBudget
  case runBudget
  case notSkippable
  case recordedAction

  /// The text of the `stop-reason` metadata and of the finding detail.
  public var text: String {
    switch self {
    case .disabled: "skipping is disabled"
    case .persistent(let key, let consecutive, let failures, let attempts):
      "\(key) is persistently missing (\(consecutive) consecutive, \(failures) of \(attempts) attempts failed)"
    case .repeatedInRun: "the same control failed again in this run"
    case .consecutiveBudget: "too many skips in a row"
    case .runBudget: "the skip budget of the run is spent"
    case .notSkippable: "the failure cannot be skipped"
    case .recordedAction: "the action was recorded, so it never skips"
    }
  }
}

public enum SkipDecision: Equatable, Sendable {
  case skip(SkippedAction)
  case terminal(TerminalReason)
}

public struct SkippedAction: Codable, Equatable, Sendable {
  /// The 1-based position the action would have had in the executed trace.
  public var slot: Int
  public var kind: String
  public var key: String
  /// The control's identity within the run, where an unnamed control is told apart by its path.
  public var runKey: String
  public var signature: String
  public var diagnostics: String?

  public init(
    slot: Int, kind: String, key: String, runKey: String, signature: String,
    diagnostics: String? = nil
  ) {
    self.slot = slot
    self.kind = kind
    self.key = key
    self.runKey = runKey
    self.signature = signature
    self.diagnostics = diagnostics
  }
}

public struct ControlStats: Codable, Equatable, Sendable {
  public var attempts = 0
  public var failures = 0
  public var consecutive = 0
  /// A persistent verdict is reported once for the life of the ledger.
  public var reported = false

  public init() {}
}

/// Counts resolution failures of live picks across a campaign and decides which may be skipped.
/// Only the counters and the app fingerprint are stored; the skips of one run are not.
public struct SkipLedger: Codable, Equatable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case appFingerprint
    case controls
  }

  public var policy = SkipPolicy()
  public var appFingerprint: String
  public private(set) var controls: [String: ControlStats] = [:]
  public private(set) var skips: [SkippedAction] = []
  private var runConsecutive = 0
  private var runControlSkips: [String: Int] = [:]

  public init(appFingerprint: String = "", policy: SkipPolicy = SkipPolicy()) {
    self.appFingerprint = appFingerprint
    self.policy = policy
  }

  public mutating func beginRun() {
    skips = []
    runConsecutive = 0
    runControlSkips = [:]
  }

  /// A live pick that resolved, or `nil` for one that needed no control.
  public mutating func succeeded(_ request: ResolutionRequest?) {
    runConsecutive = 0
    guard let request else { return }
    var stats = controls[request.key] ?? ControlStats()
    stats.attempts += 1
    stats.consecutive = 0
    controls[request.key] = stats
  }

  /// Counts the failure first, then decides in this order: disabled, persistent (once per key),
  /// the same control again in this run, too many in a row, too many in the run.
  public mutating func failed(
    _ request: ResolutionRequest, slot: Int, kind: String, signature: String
  ) -> SkipDecision {
    var stats = controls[request.key] ?? ControlStats()
    stats.attempts += 1
    stats.failures += 1
    stats.consecutive += 1
    controls[request.key] = stats
    guard policy.maximumPerRun > 0 else { return .terminal(.disabled) }
    if !stats.reported && isPersistent(stats, named: request.target != nil) {
      controls[request.key]?.reported = true
      return .terminal(
        .persistent(
          key: request.key, consecutive: stats.consecutive, failures: stats.failures,
          attempts: stats.attempts))
    }
    if runControlSkips[request.runKey, default: 0] >= policy.maximumPerControlPerRun {
      return .terminal(.repeatedInRun)
    }
    if runConsecutive >= policy.maximumConsecutive { return .terminal(.consecutiveBudget) }
    if skips.count >= policy.maximumPerRun { return .terminal(.runBudget) }
    let skip = SkippedAction(
      slot: slot, kind: kind, key: request.key, runKey: request.runKey, signature: signature)
    skips.append(skip)
    runConsecutive += 1
    runControlSkips[request.runKey, default: 0] += 1
    return .skip(skip)
  }

  public mutating func recordDiagnostics(_ file: String) {
    precondition(!skips.isEmpty)
    skips[skips.count - 1].diagnostics = file
  }

  private func isPersistent(_ stats: ControlStats, named: Bool) -> Bool {
    (named && stats.consecutive >= policy.persistentConsecutive)
      || (stats.failures >= policy.persistentFailures
        && Double(stats.failures) >= policy.persistentRate * Double(stats.attempts))
  }

  public func summary(limit: Int = 10) -> [String] {
    controls.filter { $0.value.failures > 0 }
      .sorted { ($0.value.failures, $1.key) > ($1.value.failures, $0.key) }
      .prefix(limit)
      .map { "\($0.key): \($0.value.failures) failed of \($0.value.attempts) attempts" }
  }
}

extension SkipLedger {
  public static func fingerprint(path: String, modified: TimeInterval, size: Int) -> String {
    "\(path)@\(Int((modified * 1000).rounded()))#\(size)"
  }

  public static func opening(
    existing: SkipLedger?, appFingerprint: String, reset: Bool, policy: SkipPolicy
  ) -> (ledger: SkipLedger, notice: String?) {
    guard let existing else {
      return (SkipLedger(appFingerprint: appFingerprint, policy: policy), nil)
    }
    if reset {
      return (
        SkipLedger(appFingerprint: appFingerprint, policy: policy),
        "Started an empty skip ledger because --reset-skip-ledger was given."
      )
    }
    if existing.appFingerprint != appFingerprint {
      return (
        SkipLedger(appFingerprint: appFingerprint, policy: policy),
        "Started an empty skip ledger because the app changed since it was written."
      )
    }
    var kept = existing
    kept.policy = policy
    return (kept, nil)
  }

  /// A missing file is no ledger; a file that cannot be decoded throws.
  public static func load(from url: URL) throws -> SkipLedger? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(SkipLedger.self, from: Data(contentsOf: url))
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
