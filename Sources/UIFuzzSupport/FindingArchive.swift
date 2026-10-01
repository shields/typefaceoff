import Foundation

public struct FindingIdentity: Codable, Equatable, Hashable, Sendable {
  public let kind: ExecutionFinding.Kind
  public let signature: String

  public init(kind: ExecutionFinding.Kind, signature: String) {
    self.kind = kind
    self.signature = signature
  }
}

public struct FindingOccurrence: Codable, Equatable, Sendable {
  public let finding: FindingIdentity
  public let report: String
  public private(set) var occurrences: Int
  public let firstExecution: String
  public private(set) var latestExecution: String
  public let firstSeenAt: Date
  public private(set) var latestSeenAt: Date

  fileprivate init(
    finding: FindingIdentity, report: String, execution: String, seenAt: Date
  ) {
    self.finding = finding
    self.report = report
    occurrences = 1
    firstExecution = execution
    latestExecution = execution
    firstSeenAt = seenAt
    latestSeenAt = seenAt
  }

  fileprivate mutating func record(execution: String, seenAt: Date) {
    occurrences += 1
    latestExecution = execution
    latestSeenAt = seenAt
  }
}

public struct FindingOccurrenceIndex: Codable, Equatable, Sendable {
  public private(set) var findings: [FindingOccurrence] = []

  public init() {}

  fileprivate mutating func record(
    _ identities: Set<FindingIdentity>, reportByFinding: [FindingIdentity: String],
    execution: String, seenAt: Date
  ) {
    for identity in identities {
      if let index = findings.firstIndex(where: { $0.finding == identity }) {
        findings[index].record(execution: execution, seenAt: seenAt)
      } else {
        findings.append(
          FindingOccurrence(
            finding: identity, report: reportByFinding[identity]!, execution: execution,
            seenAt: seenAt))
      }
    }
    findings.sort {
      ($0.finding.kind.rawValue, $0.finding.signature)
        < ($1.finding.kind.rawValue, $1.finding.signature)
    }
  }
}

public struct FindingArchive {
  public static let indexName = "finding-occurrences.json"

  public let artifacts: URL
  public private(set) var index: FindingOccurrenceIndex

  private var indexURL: URL { artifacts.appending(path: Self.indexName) }

  private init(artifacts: URL, index: FindingOccurrenceIndex) {
    self.artifacts = artifacts
    self.index = index
  }

  public static func open(in artifacts: URL) throws -> FindingArchive {
    let indexURL = artifacts.appending(path: indexName)
    if let index = try ArtifactLoader.findingOccurrenceIndex(at: indexURL) {
      let archive = FindingArchive(artifacts: artifacts, index: index)
      try archive.validateIndex(at: indexURL)
      return archive
    }
    var archive = FindingArchive(artifacts: artifacts, index: FindingOccurrenceIndex())
    try archive.importExistingReports()
    return archive
  }

  public mutating func preserve(
    _ report: ExecutionReport, execution: String
  ) throws -> [FindingIdentity: URL] {
    let identities = identities(in: report)
    guard !identities.isEmpty else { return [:] }
    let existing = Dictionary(uniqueKeysWithValues: index.findings.map { ($0.finding, $0.report) })
    let newKinds = Set(identities.filter { existing[$0] == nil }.map(\.kind))
    var reportByFinding = existing
    for kind in newKinds {
      let relative = "findings/\(kind.rawValue)/\(execution).json"
      try TraceIO.save(report.withoutCoverage, to: artifacts.appending(path: relative))
      for identity in identities where identity.kind == kind && existing[identity] == nil {
        reportByFinding[identity] = relative
      }
    }
    index.record(
      identities, reportByFinding: reportByFinding, execution: execution,
      seenAt: report.startedAt)
    try saveIndex()
    return Dictionary(
      uniqueKeysWithValues: identities.map { identity in
        let occurrence = index.findings.first { $0.finding == identity }!
        return (identity, artifacts.appending(path: occurrence.report))
      })
  }

  private mutating func importExistingReports() throws {
    let findingsRoot = artifacts.appending(path: "findings")
    var allReports = Set<String>()
    for kind in ExecutionFinding.Kind.allCases where kind != .slow {
      let directory = findingsRoot.appending(path: kind.rawValue)
      guard FileManager.default.fileExists(atPath: directory.path) else { continue }
      for url in try ArtifactLoader.jsonFiles(in: directory) {
        let report = try ArtifactLoader.existingReport(at: url)!
        let identities = identities(in: report).filter { $0.kind == kind }
        guard !identities.isEmpty else {
          throw ArtifactLoadError(
            file: url, reason: "it does not contain a \(kind.rawValue) finding")
        }
        let relative = "findings/\(kind.rawValue)/\(url.lastPathComponent)"
        let reportByFinding = Dictionary(uniqueKeysWithValues: identities.map { ($0, relative) })
        index.record(
          identities, reportByFinding: reportByFinding,
          execution: url.deletingPathExtension().lastPathComponent, seenAt: report.startedAt)
        allReports.insert(relative)
      }
    }
    guard !index.findings.isEmpty else { return }
    let retained = Set(index.findings.map(\.report))
    for path in retained {
      let url = artifacts.appending(path: path)
      let report = try ArtifactLoader.existingReport(at: url)!
      try TraceIO.save(report.withoutCoverage, to: url)
    }
    try saveIndex()
    for path in allReports.subtracting(retained) {
      try FileManager.default.removeItem(at: artifacts.appending(path: path))
    }
  }

  private func identities(in report: ExecutionReport) -> Set<FindingIdentity> {
    Set(
      report.findings.compactMap { finding in
        finding.kind == .slow
          ? nil : FindingIdentity(kind: finding.kind, signature: finding.signature)
      })
  }

  private func validateIndex(at url: URL) throws {
    var seen = Set<FindingIdentity>()
    var reports: [String: ExecutionReport] = [:]
    for occurrence in index.findings {
      guard occurrence.occurrences > 0 else {
        throw ArtifactLoadError(file: url, reason: "a finding has no occurrences")
      }
      guard seen.insert(occurrence.finding).inserted else {
        throw ArtifactLoadError(file: url, reason: "a finding appears more than once")
      }
      let parts = occurrence.report.split(separator: "/", omittingEmptySubsequences: false)
      guard parts.count == 3, parts[0] == "findings",
        parts[1] == occurrence.finding.kind.rawValue, parts[2].hasSuffix(".json")
      else {
        throw ArtifactLoadError(file: url, reason: "a finding report path is invalid")
      }
      let report: ExecutionReport
      if let loaded = reports[occurrence.report] {
        report = loaded
      } else {
        let reportURL = artifacts.appending(path: occurrence.report)
        guard let loaded = try ArtifactLoader.existingReport(at: reportURL) else {
          throw ArtifactLoadError(file: url, reason: "a finding report is missing")
        }
        reports[occurrence.report] = loaded
        report = loaded
      }
      guard identities(in: report).contains(occurrence.finding) else {
        throw ArtifactLoadError(file: url, reason: "a report does not contain its finding")
      }
    }
  }

  private func saveIndex() throws {
    try FileManager.default.createDirectory(
      at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(index).write(to: indexURL, options: .atomic)
  }
}

extension ExecutionReport {
  fileprivate var withoutCoverage: ExecutionReport {
    var report = self
    report.coverage = []
    report.countBuckets = []
    return report
  }
}
