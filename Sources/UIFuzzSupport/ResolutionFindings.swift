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

public enum ResolutionFindings {
  public enum SideFile: String, Sendable {
    case diagnostics = "diagnostics-write"
    case driverLog = "driver-log-write"

    var subject: String {
      switch self {
      case .diagnostics: "a diagnostics file"
      case .driverLog: "the driver log"
      }
    }
  }

  public static let candidateLimit = 8
  public static let visibleElementLimit = 100

  public struct Detail: Sendable {
    /// The 1-based position of the action in the executed trace.
    public var action: Int
    public var error: String
    /// `ResolutionFailure.reason`, when the failure is a resolution failure.
    public var reason: String?
    public var attempts: Int
    public var elapsedMilliseconds: Int
    public var telemetry: TelemetrySummary
    public var scope: TreeDump.Scope?
    public var candidates: [TreeDump.Entry]
    public var skipped: [SkippedAction]
    public var stopReason: TerminalReason?
    /// Where the dump was written, relative to the artifacts folder.
    public var diagnostics: String?
    public var visibleElements: [String]

    public init(
      action: Int, error: String, reason: String? = nil, attempts: Int, elapsedMilliseconds: Int,
      telemetry: TelemetrySummary, scope: TreeDump.Scope? = nil,
      candidates: [TreeDump.Entry] = [], skipped: [SkippedAction] = [],
      stopReason: TerminalReason? = nil, diagnostics: String? = nil,
      visibleElements: [String] = []
    ) {
      self.action = action
      self.error = error
      self.reason = reason
      self.attempts = attempts
      self.elapsedMilliseconds = elapsedMilliseconds
      self.telemetry = telemetry
      self.scope = scope
      self.candidates = candidates
      self.skipped = skipped
      self.stopReason = stopReason
      self.diagnostics = diagnostics
      self.visibleElements = visibleElements
    }
  }

  /// A persistently missing control is named by its key and everything else by its error, so the
  /// signature of a missing control stays stable across campaigns.
  public static func signature(for failure: SlotFailure) -> String {
    if case .persistent(let key, _, _, _) = failure.reason {
      return ResolutionSignature.persistent + key
    }
    return String(describing: failure.underlying)
  }

  /// One line, ending with the visible elements because scripts read that list to the end of the
  /// line.
  public static func detail(_ detail: Detail) -> String {
    var sentences = ["Action \(detail.action): \(detail.error)."]
    if let reason = detail.reason { sentences.append("\(reason).") }
    sentences.append("Attempts: \(detail.attempts) over \(detail.elapsedMilliseconds) ms.")
    sentences.append("Pending work: \(detail.telemetry.pendingSummary).")
    if let scope = detail.scope {
      let window = scope.selectedIndex.map { "window child \($0)" } ?? "no window"
      sentences.append(
        "Scope: \(scope.source.rawValue), \(window), standard windows: \(scope.standardWindows).")
    }
    if !detail.candidates.isEmpty {
      let listed = detail.candidates.prefix(candidateLimit).map {
        "\($0.path) \($0.role) \"\($0.displayName)\""
      }.joined(separator: "; ")
      let more = detail.candidates.count - candidateLimit
      sentences.append("Ambiguous candidates: \(listed)\(more > 0 ? " (+\(more) more)" : "").")
    }
    if !detail.skipped.isEmpty {
      let keys = detail.skipped.map(\.key).joined(separator: "; ")
      sentences.append("Skipped earlier: \(detail.skipped.count) (\(keys)).")
    }
    if let stopReason = detail.stopReason { sentences.append("Stop reason: \(stopReason.text).") }
    if let diagnostics = detail.diagnostics { sentences.append("Diagnostics: \(diagnostics).") }
    let visible = detail.visibleElements.prefix(visibleElementLimit).joined(separator: ", ")
    sentences.append("Visible accessibility elements: \(visible)")
    return sentences.joined(separator: " ")
  }

  public static func finding(for failure: SlotFailure, detail text: Detail) -> ExecutionFinding {
    ExecutionFinding(
      kind: .automation, signature: signature(for: failure), detail: detail(text))
  }

  /// A side file the fuzzer could not write is a finding of its own, never a warning.
  public static func sideFileFailure(_ file: SideFile, error: any Error) -> ExecutionFinding {
    ExecutionFinding(
      kind: .automation, signature: file.rawValue,
      detail: "Could not write \(file.subject): \(error)")
  }

  /// Primary findings first, in their original order, then failures of the fuzzer's own side
  /// files, so the first finding of a report is always the one Minimize should target.
  public static func ordered(_ findings: [ExecutionFinding]) -> [ExecutionFinding] {
    findings.filter { !$0.isSideFileFailure } + findings.filter(\.isSideFileFailure)
  }
}

public struct ResolutionMetadata: Equatable, Sendable {
  public private(set) var steps: [ResolutionStep: Int] = [:]
  public private(set) var retries = 0
  public private(set) var diagnostics: [String] = []
  public var stopReason: TerminalReason?
  /// Live picks waited for the app to be quiet, which recorded traces replay without.
  public var idleGated = false

  public init() {}

  public mutating func recordResolution(attempts: Int, step: ResolutionStep?) {
    if attempts > 1 { retries += 1 }
    if let step { steps[step, default: 0] += 1 }
  }

  public mutating func recordDiagnostics(_ file: String) {
    diagnostics.append(file)
  }

  /// `path:27 uniqueName:3`, in step order, or empty when nothing resolved.
  public var stepSummary: String {
    ResolutionStep.allCases.compactMap { step in steps[step].map { "\(step.rawValue):\($0)" } }
      .joined(separator: " ")
  }

  public static func progressSuffix(skips: Int) -> String {
    skips > 0 ? " skips=\(skips)" : ""
  }

  public func entries(skips: [SkippedAction], idle: IdleBudget?) -> [String: String] {
    var result = [
      "skipped-actions": String(skips.count),
      "resolve-retries": String(retries),
    ]
    if !steps.isEmpty { result["resolution-steps"] = stepSummary }
    if !skips.isEmpty {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      result["skips"] = String(decoding: try! encoder.encode(skips), as: UTF8.self)
    }
    if !diagnostics.isEmpty { result["diagnostics"] = diagnostics.joined(separator: ",") }
    if let stopReason { result["stop-reason"] = stopReason.text }
    if idleGated { result["live-idle-gated"] = "true" }
    if let idle {
      result["idle-wait-ms"] = String(idle.spent * 1000)
      result["idle-wait-timeouts"] = String(idle.timeouts)
      result["idle-waits"] = String(idle.waits)
      result["idle-wait-skipped"] = String(idle.skipped)
    }
    return result
  }
}
