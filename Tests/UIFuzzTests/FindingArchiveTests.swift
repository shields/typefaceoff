import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct FindingArchiveTests {
  private let automation = ExecutionFinding(
    kind: .automation, signature: "could-not-press", detail: "Could not press the control.")
  private let anotherAutomation = ExecutionFinding(
    kind: .automation, signature: "could-not-find", detail: "Could not find the control.")
  private let finalAutomation = ExecutionFinding(
    kind: .automation, signature: "could-not-read", detail: "Could not read the control.")
  private let correctness = ExecutionFinding(
    kind: .correctness, signature: "invariant", detail: "An invariant failed.")
  private let slow = ExecutionFinding(
    kind: .slow, signature: "campaign-tail", detail: "A slow run.")

  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func report(
    at seconds: TimeInterval, findings: [ExecutionFinding], seed: UInt64 = 1
  ) -> ExecutionReport {
    ExecutionReport(
      trace: FuzzTrace(seed: seed), startedAt: Date(timeIntervalSince1970: seconds),
      durationMilliseconds: 10, actionMilliseconds: [], coverage: ["region"],
      countBuckets: ["region=1"], findings: findings)
  }

  @Test func newFindingsKeepOneCompactReportAndRepeatsOnlyUpdateTheIndex() throws {
    let artifacts = try folder()
    defer { try? FileManager.default.removeItem(at: artifacts) }
    var archive = try FindingArchive.open(in: artifacts)
    #expect(archive.index.findings.isEmpty)
    #expect(
      !FileManager.default.fileExists(
        atPath: artifacts.appending(path: FindingArchive.indexName).path))

    let automationID = FindingIdentity(kind: .automation, signature: automation.signature)
    let anotherID = FindingIdentity(kind: .automation, signature: anotherAutomation.signature)
    let finalID = FindingIdentity(kind: .automation, signature: finalAutomation.signature)
    let correctnessID = FindingIdentity(kind: .correctness, signature: correctness.signature)
    let firstReferences = try archive.preserve(
      report(at: 1, findings: [automation, automation, correctness, slow]), execution: "first")
    let firstAutomation = artifacts.appending(path: "findings/automation/first.json")
    let firstCorrectness = artifacts.appending(path: "findings/correctness/first.json")
    #expect(firstReferences == [automationID: firstAutomation, correctnessID: firstCorrectness])
    for url in [firstAutomation, firstCorrectness] {
      let saved = try #require(try ArtifactLoader.existingReport(at: url))
      #expect(saved.coverage.isEmpty)
      #expect(saved.countBuckets.isEmpty)
      #expect(saved.findings == [automation, automation, correctness, slow])
    }

    let secondReferences = try archive.preserve(
      report(
        at: 2, findings: [automation, anotherAutomation, finalAutomation, correctness], seed: 2),
      execution: "second")
    let secondAutomation = artifacts.appending(path: "findings/automation/second.json")
    #expect(secondReferences[automationID] == firstAutomation)
    #expect(secondReferences[anotherID] == secondAutomation)
    #expect(secondReferences[finalID] == secondAutomation)
    #expect(secondReferences[correctnessID] == firstCorrectness)
    #expect(
      try ArtifactLoader.jsonFiles(in: artifacts.appending(path: "findings/automation"))
        .map(\.lastPathComponent) == ["first.json", "second.json"])
    #expect(
      try ArtifactLoader.jsonFiles(in: artifacts.appending(path: "findings/correctness"))
        .map(\.lastPathComponent) == ["first.json"])

    archive = try FindingArchive.open(in: artifacts)
    let thirdReferences = try archive.preserve(
      report(
        at: 3, findings: [automation, anotherAutomation, finalAutomation, correctness], seed: 3),
      execution: "third")
    #expect(thirdReferences == secondReferences)
    #expect(
      !FileManager.default.fileExists(
        atPath: artifacts.appending(path: "findings/automation/third.json").path))
    let occurrences = Dictionary(
      uniqueKeysWithValues: archive.index.findings.map { ($0.finding, $0) })
    #expect(occurrences[automationID]?.occurrences == 3)
    #expect(occurrences[automationID]?.firstExecution == "first")
    #expect(occurrences[automationID]?.latestExecution == "third")
    #expect(occurrences[automationID]?.firstSeenAt == Date(timeIntervalSince1970: 1))
    #expect(occurrences[automationID]?.latestSeenAt == Date(timeIntervalSince1970: 3))
    #expect(occurrences[anotherID]?.occurrences == 2)
    #expect(occurrences[finalID]?.occurrences == 2)
    #expect(occurrences[correctnessID]?.occurrences == 3)
    #expect(
      try ArtifactLoader.findingOccurrenceIndex(
        at: artifacts.appending(path: FindingArchive.indexName)) == archive.index)
  }

  @Test func reportsWithoutArchivableFindingsCreateNothing() throws {
    let artifacts = try folder()
    defer { try? FileManager.default.removeItem(at: artifacts) }
    var archive = try FindingArchive.open(in: artifacts)
    #expect(try archive.preserve(report(at: 1, findings: []), execution: "clean").isEmpty)
    #expect(try archive.preserve(report(at: 2, findings: [slow]), execution: "slow").isEmpty)
    #expect(archive.index.findings.isEmpty)
    #expect(
      !FileManager.default.fileExists(
        atPath: artifacts.appending(path: FindingArchive.indexName).path))
  }

  @Test func openingAnOldArtifactTreeCompactsAndIndexesItsReports() throws {
    let artifacts = try folder()
    defer { try? FileManager.default.removeItem(at: artifacts) }
    let automationDirectory = artifacts.appending(path: "findings/automation")
    let correctnessDirectory = artifacts.appending(path: "findings/correctness")
    let slowDirectory = artifacts.appending(path: "findings/slow")
    let first = automationDirectory.appending(path: "00000001-a.json")
    let second = automationDirectory.appending(path: "00000002-b.json")
    let redundant = automationDirectory.appending(path: "00000003-c.json")
    let correctnessReport = correctnessDirectory.appending(path: "00000004-d.json")
    let slowReport = slowDirectory.appending(path: "00000005-e.json")
    try TraceIO.save(report(at: 1, findings: [automation]), to: first)
    try TraceIO.save(report(at: 2, findings: [automation, anotherAutomation]), to: second)
    try TraceIO.save(report(at: 3, findings: [automation]), to: redundant)
    try TraceIO.save(report(at: 4, findings: [correctness]), to: correctnessReport)
    try TraceIO.save(report(at: 5, findings: [slow]), to: slowReport)

    let archive = try FindingArchive.open(in: artifacts)

    let occurrences = Dictionary(
      uniqueKeysWithValues: archive.index.findings.map { ($0.finding, $0) })
    let automationID = FindingIdentity(kind: .automation, signature: automation.signature)
    let anotherID = FindingIdentity(kind: .automation, signature: anotherAutomation.signature)
    let correctnessID = FindingIdentity(kind: .correctness, signature: correctness.signature)
    #expect(occurrences[automationID]?.occurrences == 3)
    #expect(occurrences[automationID]?.report == "findings/automation/00000001-a.json")
    #expect(occurrences[anotherID]?.occurrences == 1)
    #expect(occurrences[anotherID]?.report == "findings/automation/00000002-b.json")
    #expect(occurrences[correctnessID]?.occurrences == 1)
    #expect(occurrences.count == 3)
    #expect(!FileManager.default.fileExists(atPath: redundant.path))
    for url in [first, second, correctnessReport] {
      let saved = try #require(try ArtifactLoader.existingReport(at: url))
      #expect(saved.coverage.isEmpty)
      #expect(saved.countBuckets.isEmpty)
    }
    let savedSlow = try #require(try ArtifactLoader.existingReport(at: slowReport))
    #expect(savedSlow.coverage == ["region"])
    #expect(savedSlow.countBuckets == ["region=1"])
    #expect(
      FileManager.default.fileExists(
        atPath: artifacts.appending(path: FindingArchive.indexName).path))
  }

  @Test func aLegacyReportMustMatchItsFindingDirectory() throws {
    let artifacts = try folder()
    defer { try? FileManager.default.removeItem(at: artifacts) }
    let url = artifacts.appending(path: "findings/crash/wrong.json")
    try TraceIO.save(report(at: 1, findings: [automation]), to: url)

    let failure = try #require(throws: ArtifactLoadError.self) {
      _ = try FindingArchive.open(in: artifacts)
    }
    #expect(failure.file.lastPathComponent == url.lastPathComponent)
    #expect(failure.reason == "it does not contain a crash finding")
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(
      !FileManager.default.fileExists(
        atPath: artifacts.appending(path: FindingArchive.indexName).path))
  }

  @Test func anExistingIndexMustBeConsistentWithItsReports() throws {
    let cases: [(String, (URL, URL) throws -> Void)] = [
      (
        "a finding has no occurrences",
        { _, indexURL in
          try editIndex(at: indexURL) { findings in findings[0]["occurrences"] = 0 }
        }
      ),
      (
        "a finding appears more than once",
        { _, indexURL in
          try editIndex(at: indexURL) { findings in findings.append(findings[0]) }
        }
      ),
      (
        "a finding report path is invalid",
        { _, indexURL in
          try editIndex(at: indexURL) { findings in findings[0]["report"] = "../outside.json" }
        }
      ),
      (
        "a finding report is missing",
        { _, indexURL in
          try editIndex(at: indexURL) { findings in
            findings[0]["report"] = "findings/automation/missing.json"
          }
        }
      ),
      (
        "a report does not contain its finding",
        { artifacts, _ in
          try TraceIO.save(
            report(at: 2, findings: [correctness]),
            to: artifacts.appending(path: "findings/automation/first.json"))
        }
      ),
    ]

    for (reason, corrupt) in cases {
      let artifacts = try folder()
      var archive = try FindingArchive.open(in: artifacts)
      _ = try archive.preserve(report(at: 1, findings: [automation]), execution: "first")
      let indexURL = artifacts.appending(path: FindingArchive.indexName)
      try corrupt(artifacts, indexURL)
      let failure = try #require(throws: ArtifactLoadError.self) {
        _ = try FindingArchive.open(in: artifacts)
      }
      #expect(failure.file.lastPathComponent == FindingArchive.indexName)
      #expect(failure.reason == reason)
      try FileManager.default.removeItem(at: artifacts)
    }
  }

  private func editIndex(
    at url: URL, _ edit: (inout [[String: Any]]) -> Void
  ) throws {
    var object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var findings = try #require(object["findings"] as? [[String: Any]])
    edit(&findings)
    object["findings"] = findings
    try JSONSerialization.data(withJSONObject: object).write(to: url)
  }
}
