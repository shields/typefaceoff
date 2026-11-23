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

@Suite struct ArtifactRetentionTests {
  private func report(run: String?) -> ExecutionReport {
    ExecutionReport(
      trace: FuzzTrace(seed: 1), startedAt: Date(timeIntervalSince1970: 1),
      durationMilliseconds: 1, actionMilliseconds: [], metadata: run.map { ["run": $0] } ?? [:])
  }

  @Test func coverageProfilesAreDiscardedWithoutRemovingOtherRunEvidence() throws {
    let artifacts = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: artifacts) }
    let run = UUID().uuidString
    let directory = artifacts.appending(path: "runs/\(run)")
    try FileManager.default.createDirectory(
      at: directory.appending(path: "nested.profraw"), withIntermediateDirectories: true)
    for name in ["coverage.profdata", "123.profraw", "stderr.log", "profile.profraw.txt"] {
      try Data(name.utf8).write(to: directory.appending(path: name))
    }

    try ArtifactRetention.discardCoverageArtifacts(for: report(run: run), in: artifacts)

    #expect(
      !FileManager.default.fileExists(atPath: directory.appending(path: "coverage.profdata").path))
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "123.profraw").path))
    for name in ["stderr.log", "profile.profraw.txt", "nested.profraw"] {
      #expect(FileManager.default.fileExists(atPath: directory.appending(path: name).path))
    }
  }

  @Test func aMissingRunDirectoryHasNothingToDiscard() throws {
    let artifacts = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try ArtifactRetention.discardCoverageArtifacts(
      for: report(run: UUID().uuidString), in: artifacts)
  }

  @Test(arguments: [nil, "not-a-uuid"] as [String?])
  func aRunIdentifierMustBeAUUID(run: String?) {
    let failure = #expect(throws: ArtifactRetentionError.self) {
      try ArtifactRetention.discardCoverageArtifacts(
        for: report(run: run), in: FileManager.default.temporaryDirectory)
    }
    #expect(failure?.run == run)
    #expect(failure?.description.contains("no valid run UUID") == true)
    #expect(failure?.errorDescription == failure?.description)
  }
}
