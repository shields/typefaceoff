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
