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

public enum ExecutionJournal {
  public static func append(_ value: some Encodable, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    var data = try encoder.encode(value)
    data.append(0x0A)
    let handle = try DriverLog.open(url)
    defer { try! handle.close() }
    try handle.write(contentsOf: data)
  }
}

public struct ExecutionRecord: Encodable, Sendable {
  public var execution: String
  public var startedAt: Date
  public var durationMilliseconds: Double
  public var measuredMilliseconds: Double
  public var seed: UInt64
  public var origin: String
  public var attempted: Int
  public var completed: Int
  public var settled: Int
  public var coverageRegions: Int
  public var coverageBuckets: Int
  public var findings: [ExecutionFinding]
  public var metadata: [String: String]

  public init(_ report: ExecutionReport, timings: [ActionTiming]) {
    execution = report.metadata["run"] ?? ""
    startedAt = report.startedAt
    durationMilliseconds = report.durationMilliseconds
    measuredMilliseconds = report.measuredMilliseconds
    seed = report.trace.seed
    origin = report.trace.origin
    attempted = timings.count
    completed = report.actionMilliseconds.count
    settled = timings.filter { $0.result == .settled }.count
    coverageRegions = report.coverage.count
    coverageBuckets = report.countBuckets.count
    findings = report.findings
    metadata = report.metadata.filter { $0.key != "final-snapshot" }
  }
}
