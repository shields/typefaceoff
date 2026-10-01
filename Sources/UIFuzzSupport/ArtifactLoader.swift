import Foundation

public struct ArtifactLoadError: Error, LocalizedError, CustomStringConvertible, Equatable {
  public let file: URL
  public let reason: String

  public init(file: URL, reason: String) {
    self.file = file
    self.reason = reason
  }

  public var description: String { "Cannot load \(file.path): \(reason)" }
  public var errorDescription: String? { description }
}

public enum ArtifactLoader {
  public static func jsonFiles(in directory: URL) throws -> [URL] {
    do {
      return try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.isDirectoryKey]
      ).filter {
        try $0.pathExtension == "json"
          && $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true
      }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    } catch {
      throw ArtifactLoadError(file: directory, reason: String(describing: error))
    }
  }

  public static func corpus(in directory: URL) throws -> [FuzzTrace] {
    try jsonFiles(in: directory).map { file in
      do {
        return try TraceIO.load(file)
      } catch TraceIO.TraceError.unsupportedVersion(let version) {
        throw ArtifactLoadError(
          file: file,
          reason:
            "trace schema version \(version), but this build reads version \(FuzzTrace.schemaVersion)"
        )
      } catch {
        throw ArtifactLoadError(file: file, reason: String(describing: error))
      }
    }
  }

  public static func corpusState(at url: URL) throws -> CorpusState {
    try decodeIfPresent(CorpusState.self, at: url, decoder: JSONDecoder()) ?? CorpusState()
  }

  public static func existingReport(at url: URL) throws -> ExecutionReport? {
    try decodeIfPresent(ExecutionReport.self, at: url, decoder: reportDecoder())
  }

  public static func findingOccurrenceIndex(at url: URL) throws -> FindingOccurrenceIndex? {
    try decodeIfPresent(FindingOccurrenceIndex.self, at: url, decoder: reportDecoder())
  }

  /// Reports that rank below `keeping` are deleted; a file that is not a slow report throws and is
  /// left in place.
  public static func slowCandidates(in directory: URL, keeping limit: Int) throws -> [(
    Double, URL
  )] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    var candidates: [(Double, URL)] = []
    for url in try jsonFiles(in: directory) {
      let report = try decode(ExecutionReport.self, at: url, decoder: reportDecoder())
      guard report.workloadDurationMilliseconds != nil, !report.findings.isEmpty,
        report.findings.allSatisfy({ $0.kind == .slow })
      else {
        throw ArtifactLoadError(
          file: url, reason: "it is not a slow report of a completed run")
      }
      candidates.append((report.measuredMilliseconds, url))
    }
    candidates.sort { $0.0 > $1.0 }
    for (_, url) in candidates.dropFirst(limit) {
      try FileManager.default.removeItem(at: url)
    }
    return Array(candidates.prefix(limit))
  }

  private static func reportDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private static func decodeIfPresent<Value: Decodable>(
    _ type: Value.Type, at url: URL, decoder: JSONDecoder
  ) throws -> Value? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try decode(type, at: url, decoder: decoder)
  }

  private static func decode<Value: Decodable>(
    _ type: Value.Type, at url: URL, decoder: JSONDecoder
  ) throws -> Value {
    do {
      return try decoder.decode(type, from: Data(contentsOf: url))
    } catch {
      throw ArtifactLoadError(file: url, reason: String(describing: error))
    }
  }
}
