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
