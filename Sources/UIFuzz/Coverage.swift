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
import UIFuzzSupport

struct CoverageResult {
  var regions: Set<String>
  var countBuckets: Set<String>
}

enum CoverageReader {
  static func read(rawProfile: URL, binary: URL, workingDirectory: URL) throws -> CoverageResult {
    let profile = workingDirectory.appending(path: "coverage.profdata")
    _ = try run(
      "/usr/bin/xcrun",
      arguments: ["llvm-profdata", "merge", rawProfile.path, "-o", profile.path],
      workingDirectory: workingDirectory)
    let data = try run(
      "/usr/bin/xcrun",
      arguments: ["llvm-cov", "export", binary.path, "-instr-profile=\(profile.path)"],
      workingDirectory: workingDirectory)
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let datasets = root?["data"] as? [[String: Any]] ?? []
    var regions = Set<String>()
    var buckets = Set<String>()
    for dataset in datasets {
      for file in dataset["files"] as? [[String: Any]] ?? [] {
        guard let filename = file["filename"] as? String,
          filename.contains("/Sources/Typeface"),
          !filename.hasSuffix("/FuzzDiagnostics.swift")
        else { continue }
        for segment in file["segments"] as? [[Any]] ?? [] {
          guard segment.count >= 3, let line = segment[0] as? Int,
            let column = segment[1] as? Int, let count = segment[2] as? Int, count > 0
          else { continue }
          guard let source = filename.range(of: "/Sources/") else { continue }
          let identity = "\(filename[source.upperBound...]):\(line):\(column)"
          regions.insert(identity)
          buckets.insert("\(identity)=\(CoverageBuckets.bucket(count))")
        }
      }
    }
    return CoverageResult(regions: regions, countBuckets: buckets)
  }

  private static func run(
    _ executable: String, arguments: [String], workingDirectory: URL
  ) throws -> Data {
    let process = Process()
    let identifier = UUID().uuidString
    let outputURL = workingDirectory.appending(path: ".command-\(identifier).stdout")
    let errorsURL = workingDirectory.appending(path: ".command-\(identifier).stderr")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorsURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)
    let errors = try FileHandle(forWritingTo: errorsURL)
    defer {
      try? output.close()
      try? errors.close()
      try? FileManager.default.removeItem(at: outputURL)
      try? FileManager.default.removeItem(at: errorsURL)
    }
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    try output.synchronize()
    try errors.synchronize()
    let data = try Data(contentsOf: outputURL)
    guard process.terminationStatus == 0 else {
      let message = String(decoding: try Data(contentsOf: errorsURL), as: UTF8.self)
      throw CoverageError.command(message)
    }
    return data
  }

  enum CoverageError: Error { case command(String) }
}
