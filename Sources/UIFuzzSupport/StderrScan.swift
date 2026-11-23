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

public struct StderrLogError: Error, LocalizedError, CustomStringConvertible, Equatable {
  public let url: URL

  public var description: String {
    "The app reached its diagnostics but left no stderr log at \(url.path)."
  }

  public var errorDescription: String? { description }
}

/// Turns anything the fuzzed app wrote to stderr into a correctness finding. A healthy run writes
/// nothing, so output is evidence, such as a runtime warning that will become an assertion.
public enum StderrScan {
  public static let signaturePrefix = "app-stderr: "

  /// Substrings of normalized lines that are known to be harmless and are not evidence. Each entry
  /// needs a comment saying why the line is benign.
  public static let allowedSubstrings: [String] = [
    // SwiftUI's List logs this on macOS 27 when it fills past the viewport, in both pickers. The
    // app has no table delegate of its own. It becomes an assert in a future release, and a
    // crash is then a finding by itself.
    "performed a reentrant operation in its NSTableView delegate"
  ]

  public static let defaultReadLimit = 4 << 20

  static let distinctLineLimit = 5
  static let lineLength = 300
  static let signatureLength = 200

  /// NSLog starts every line with a timestamp, the process name, and the pid and thread, which
  /// differ on each occurrence of the same message.
  private static let linePrefixPattern =
    #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+(?: ?[+-]\d{4})? [^\[\]]+\[\d+:[0-9a-fA-F]+\](?: |$)"#

  /// A missing log is an error unless `absentIsEmpty`, which the caller sets for an app that died
  /// before it could open the log.
  public static func finding(
    logAt url: URL, absentIsEmpty: Bool, readLimit: Int = defaultReadLimit,
    allowing allowed: [String] = allowedSubstrings
  ) throws -> ExecutionFinding? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      if absentIsEmpty { return nil }
      throw StderrLogError(url: url)
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: readLimit + 1) ?? Data()
    let truncated = data.count > readLimit
    return finding(
      in: String(decoding: data.prefix(readLimit), as: UTF8.self), truncated: truncated,
      allowing: allowed)
  }

  public static func finding(
    in text: String, truncated: Bool = false, allowing allowed: [String] = allowedSubstrings
  ) -> ExecutionFinding? {
    let prefix = try! Regex(linePrefixPattern)
    var entries: [(line: String, count: Int)] = []
    var positions: [String: Int] = [:]
    var total = 0
    for raw in text.split(whereSeparator: \.isNewline) {
      let line = normalize(raw, removing: prefix)
      guard !line.isEmpty, !allowed.contains(where: { line.contains($0) }) else { continue }
      total += 1
      if let position = positions[line] {
        entries[position].count += 1
      } else {
        positions[line] = entries.count
        entries.append((line, 1))
      }
    }
    guard let first = entries.first else { return nil }
    var detail =
      "The app wrote \(total) line\(total == 1 ? "" : "s") to stderr, \(entries.count) distinct."
    if truncated { detail += " Only the start of the log was scanned." }
    for entry in entries.prefix(distinctLineLimit) {
      detail += "\n\(entry.count)x \(clipped(entry.line, to: lineLength))"
    }
    if entries.count > distinctLineLimit {
      detail += "\n... and \(entries.count - distinctLineLimit) more distinct lines."
    }
    return ExecutionFinding(
      kind: .correctness, signature: signaturePrefix + clipped(first.line, to: signatureLength),
      detail: detail)
  }

  private static func normalize(_ line: Substring, removing prefix: Regex<AnyRegexOutput>)
    -> String
  {
    var text = line.trimmingCharacters(in: .whitespaces)
    if let match = text.prefixMatch(of: prefix) {
      text.removeSubrange(match.range)
    }
    return text.trimmingCharacters(in: .whitespaces)
  }

  private static func clipped(_ text: String, to length: Int) -> String {
    text.count > length ? String(text.prefix(length)) + "..." : text
  }
}
