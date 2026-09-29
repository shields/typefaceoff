import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct ArtifactLoaderTests {
  private func makeFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  private func slowReport(workload: Double?, kind: ExecutionFinding.Kind = .slow)
    -> ExecutionReport
  {
    ExecutionReport(
      trace: FuzzTrace(seed: 1), startedAt: Date(timeIntervalSince1970: 1),
      durationMilliseconds: workload ?? 1, workloadDurationMilliseconds: workload,
      actionMilliseconds: [],
      findings: [ExecutionFinding(kind: kind, signature: "campaign-tail", detail: "slow")])
  }

  @Test func corpusLoadsTracesInNameOrderAndIgnoresOtherEntries() throws {
    let folder = try makeFolder()
    let second = FuzzTrace(seed: 2, actions: [FuzzAction(kind: .press, target: "Two")])
    let first = FuzzTrace(seed: 1, actions: [FuzzAction(kind: .press, target: "One")])
    try TraceIO.save(second, to: folder.appending(path: "b.json"))
    try TraceIO.save(first, to: folder.appending(path: "a.json"))
    try Data("not json".utf8).write(to: folder.appending(path: ".DS_Store"))
    try Data("not json".utf8).write(to: folder.appending(path: "notes.txt"))
    try FileManager.default.createDirectory(
      at: folder.appending(path: "nested.json"), withIntermediateDirectories: true)
    #expect(try ArtifactLoader.corpus(in: folder) == [first, second])
  }

  @Test func corpusRejectsAMissingDirectory() throws {
    let folder = try makeFolder().appending(path: "absent")
    let failure = try #require(throws: ArtifactLoadError.self) {
      _ = try ArtifactLoader.corpus(in: folder)
    }
    #expect(failure.file == folder)
    #expect(failure.description.contains(folder.path))
    #expect(failure.errorDescription == failure.description)
  }

  @Test func corpusNamesATruncatedFileAndKeepsEveryFile() throws {
    let folder = try makeFolder()
    let good = folder.appending(path: "a.json")
    let truncated = folder.appending(path: "b.json")
    try TraceIO.save(FuzzTrace(seed: 1), to: good)
    try TraceIO.save(
      FuzzTrace(seed: 2, actions: [FuzzAction(kind: .press, target: "Text")]), to: truncated)
    let text = try Data(contentsOf: truncated)
    try text.prefix(text.count / 2).write(to: truncated)
    let failure = try #require(throws: ArtifactLoadError.self) {
      _ = try ArtifactLoader.corpus(in: folder)
    }
    #expect(failure.file.lastPathComponent == "b.json")
    #expect(
      failure.description.hasPrefix("Cannot load ") && failure.description.contains("/b.json: "))
    #expect(FileManager.default.fileExists(atPath: good.path))
    #expect(FileManager.default.fileExists(atPath: truncated.path))
  }

  @Test func corpusNamesAFileOfAnotherSchemaVersion() throws {
    let folder = try makeFolder()
    var other = FuzzTrace(seed: 3)
    other.version = FuzzTrace.schemaVersion + 1
    let url = folder.appending(path: "future.json")
    try JSONEncoder().encode(other).write(to: url)
    let failure = try #require(throws: ArtifactLoadError.self) {
      _ = try ArtifactLoader.corpus(in: folder)
    }
    #expect(failure.file.lastPathComponent == "future.json")
    #expect(
      failure.reason
        == "trace schema version \(other.version), but this build reads version \(FuzzTrace.schemaVersion)"
    )
  }

  @Test func corpusNamesAFileOfAnotherSchemaVersionWhoseShapeDoesNotDecode() throws {
    let folder = try makeFolder()
    let version = FuzzTrace.schemaVersion + 1
    try Data(#"{"version": \#(version)}"#.utf8).write(to: folder.appending(path: "reshaped.json"))
    let failure = try #require(throws: ArtifactLoadError.self) {
      _ = try ArtifactLoader.corpus(in: folder)
    }
    #expect(failure.file.lastPathComponent == "reshaped.json")
    #expect(
      failure.reason
        == "trace schema version \(version), but this build reads version \(FuzzTrace.schemaVersion)"
    )
  }

  @Test func corpusStateDefaultsWhenMissingAndRejectsCorruptFiles() throws {
    let folder = try makeFolder()
    let url = folder.appending(path: "campaign.json")
    #expect(try ArtifactLoader.corpusState(at: url) == CorpusState())
    var state = CorpusState()
    _ = state.consider(regions: ["a"], countBuckets: ["a=1"])
    try JSONEncoder().encode(state).write(to: url)
    #expect(try ArtifactLoader.corpusState(at: url) == state)
    try Data("{".utf8).write(to: url)
    let failure = try #require(throws: ArtifactLoadError.self) {
      _ = try ArtifactLoader.corpusState(at: url)
    }
    #expect(failure.file == url)
  }

  @Test func existingReportIsNilWhenMissingAndRejectsCorruptFiles() throws {
    let folder = try makeFolder()
    let url = folder.appending(path: "availability.json")
    #expect(try ArtifactLoader.existingReport(at: url) == nil)
    let report = slowReport(workload: 5)
    try TraceIO.save(report, to: url)
    #expect(try ArtifactLoader.existingReport(at: url) == report)
    try Data("[]".utf8).write(to: url)
    let failure = try #require(throws: ArtifactLoadError.self) {
      _ = try ArtifactLoader.existingReport(at: url)
    }
    #expect(failure.file == url)
  }

  @Test func slowCandidatesAreRankedAndOnlyDecodedExcessIsDeleted() throws {
    let folder = try makeFolder()
    #expect(
      try ArtifactLoader.slowCandidates(in: folder.appending(path: "absent"), keeping: 2).isEmpty)
    for (name, workload) in [("a", 10.0), ("b", 30.0), ("c", 20.0)] {
      try TraceIO.save(slowReport(workload: workload), to: folder.appending(path: "\(name).json"))
    }
    try Data("not json".utf8).write(to: folder.appending(path: ".DS_Store"))
    let kept = try ArtifactLoader.slowCandidates(in: folder, keeping: 2)
    #expect(kept.map(\.0) == [30, 20])
    #expect(kept.map { $0.1.lastPathComponent } == ["b.json", "c.json"])
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "a.json").path))
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: ".DS_Store").path))
  }

  @Test func slowCandidatesThrowWithoutDeletingWhatIsNotASlowReport() throws {
    var cleanReport = slowReport(workload: 5)
    cleanReport.findings = []
    let cases: [(String, Data)] = [
      ("undecodable", Data("{".utf8)),
      ("without-workload", try encoded(slowReport(workload: nil))),
      ("other-finding", try encoded(slowReport(workload: 5, kind: .hang))),
      ("no-finding", try encoded(cleanReport)),
    ]
    for (name, contents) in cases {
      let folder = try makeFolder()
      let stray = folder.appending(path: "\(name).json")
      try contents.write(to: stray)
      // Both reports sort before the stray file, and only one of them fits within `keeping`.
      try TraceIO.save(slowReport(workload: 1), to: folder.appending(path: "a.json"))
      try TraceIO.save(slowReport(workload: 2), to: folder.appending(path: "b.json"))
      let failure = try #require(throws: ArtifactLoadError.self) {
        _ = try ArtifactLoader.slowCandidates(in: folder, keeping: 1)
      }
      #expect(failure.file.lastPathComponent == stray.lastPathComponent)
      for kept in [stray.lastPathComponent, "a.json", "b.json"] {
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: kept).path))
      }
    }
  }

  private func encoded(_ report: ExecutionReport) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(report)
  }
}
