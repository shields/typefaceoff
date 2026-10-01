import Foundation

public struct ArtifactRetentionError: Error, LocalizedError, CustomStringConvertible, Equatable {
  public let run: String?

  public init(run: String?) {
    self.run = run
  }

  public var description: String {
    "Cannot discard coverage artifacts because the execution report has no valid run UUID"
      + (run.map { ": \($0)." } ?? ".")
  }

  public var errorDescription: String? { description }
}

public enum ArtifactRetention {
  public static func discardCoverageArtifacts(for report: ExecutionReport, in artifacts: URL) throws
  {
    guard let run = report.metadata["run"], UUID(uuidString: run) != nil else {
      throw ArtifactRetentionError(run: report.metadata["run"])
    }
    let directory = artifacts.appending(path: "runs/\(run)")
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    for url in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isRegularFileKey])
    where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
      && (url.lastPathComponent == "coverage.profdata" || url.pathExtension == "profraw")
    {
      try FileManager.default.removeItem(at: url)
    }
  }
}
