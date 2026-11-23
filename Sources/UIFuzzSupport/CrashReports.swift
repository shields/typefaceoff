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

public struct CrashReport: Equatable, Sendable {
  public var url: URL
  public var exceptionType: String?
  public var signal: String?
  public var terminationReason: String?
  public var messages: [String]

  public init(
    url: URL, exceptionType: String? = nil, signal: String? = nil,
    terminationReason: String? = nil, messages: [String] = []
  ) {
    self.url = url
    self.exceptionType = exceptionType
    self.signal = signal
    self.terminationReason = terminationReason
    self.messages = messages
  }

  public var summary: String {
    var parts: [String] = []
    if let exceptionType {
      parts.append("Exception \(exceptionType)" + (signal.map { " (\($0))" } ?? ""))
    }
    if let terminationReason { parts.append("termination \(terminationReason)") }
    for message in messages.prefix(Self.messageLimit) {
      parts.append("\"\(message.prefix(Self.messageLength))\"")
    }
    return parts.isEmpty
      ? "The report names no exception or termination reason." : parts.joined(separator: "; ")
  }

  private static let messageLimit = 5
  private static let messageLength = 300
}

public struct CrashReportSearch: Equatable, Sendable {
  public var report: CrashReport?
  /// Recent reports that could not be parsed. ReportCrash may still be writing one of them.
  public var unreadable: [String]
}

/// Finds the crash report that macOS writes for a process the driver did not quit. The file name
/// holds the process name and a timestamp but not the pid, so candidates are matched on the pid
/// and process name in the report body.
public enum CrashReports {
  public static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Logs/DiagnosticReports")
  }

  /// ReportCrash writes the file after the process is gone, and a GUI app's report in a loaded
  /// virtual machine can take several seconds. The wait happens only after an unexpected exit, so a
  /// generous bound costs little.
  public static let defaultTimeout: TimeInterval = 10

  public static func search(
    pid: pid_t, processName: String, directory: URL = defaultDirectory, since: Date
  ) throws -> CrashReportSearch {
    // ReportCrash creates the directory with the first report, so a guest that has never
    // crashed has none.
    guard FileManager.default.fileExists(atPath: directory.path) else {
      return CrashReportSearch(report: nil, unreadable: [])
    }
    var candidates: [(url: URL, modified: Date)] = []
    for url in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
    where url.pathExtension == "ips" {
      guard
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
          .contentModificationDate, modified >= since
      else { continue }
      candidates.append((url, modified))
    }
    var unreadable: [String] = []
    for candidate in candidates.sorted(by: { $0.modified > $1.modified }) {
      guard let body = try? readBody(candidate.url) else {
        unreadable.append(candidate.url.lastPathComponent)
        continue
      }
      guard body["pid"] as? Int == Int(pid), body["procName"] as? String == processName else {
        continue
      }
      return CrashReportSearch(report: report(url: candidate.url, body: body), unreadable: [])
    }
    return CrashReportSearch(report: nil, unreadable: unreadable)
  }

  public static func waitForReport(
    pid: pid_t, processName: String, directory: URL = defaultDirectory, since: Date,
    timeout: TimeInterval = defaultTimeout, pollInterval: TimeInterval = 0.25,
    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) throws -> CrashReportSearch {
    let deadline = clock() + timeout
    var result = try search(
      pid: pid, processName: processName, directory: directory, since: since)
    var remaining = deadline - clock()
    while result.report == nil && remaining > 0 {
      sleep(min(pollInterval, remaining))
      result = try search(
        pid: pid, processName: processName, directory: directory, since: since)
      remaining = deadline - clock()
    }
    return result
  }

  /// Waits for the report, copies it into the run directory, and describes the outcome for the
  /// crash finding. Every outcome, including a failure to look, is described rather than thrown so
  /// the finding still records the exit.
  public static func capture(
    pid: pid_t, processName: String, since: Date, into runDirectory: URL,
    directory: URL = defaultDirectory, timeout: TimeInterval = defaultTimeout,
    pollInterval: TimeInterval = 0.25,
    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) -> String {
    let result: CrashReportSearch
    do {
      result = try waitForReport(
        pid: pid, processName: processName, directory: directory, since: since,
        timeout: timeout, pollInterval: pollInterval, clock: clock, sleep: sleep)
    } catch {
      return "Could not search \(directory.path) for a crash report: \(error)"
    }
    guard let report = result.report else {
      var note =
        "No crash report for pid \(pid) appeared in \(directory.path) within \(Int(timeout)) s."
      if !result.unreadable.isEmpty {
        note += " Unparseable recent reports: \(result.unreadable.joined(separator: ", "))."
      }
      return note
    }
    let name = report.url.lastPathComponent
    do {
      try FileManager.default.copyItem(
        at: report.url, to: runDirectory.appending(path: name))
    } catch {
      return "Crash report \(name) was found but could not be copied into the run: \(error). "
        + report.summary
    }
    return "Crash report \(name), copied into the run: \(report.summary)"
  }

  private static func readBody(_ url: URL) throws -> [String: Any] {
    // An .ips file is a one-line JSON header followed by a JSON document.
    let data = try Data(contentsOf: url)
    guard let newline = data.firstIndex(of: 0x0a),
      let body = try JSONSerialization.jsonObject(with: data[data.index(after: newline)...])
        as? [String: Any]
    else { throw CocoaError(.fileReadCorruptFile) }
    return body
  }

  private static func report(url: URL, body: [String: Any]) -> CrashReport {
    let exception = body["exception"] as? [String: Any]
    let termination = body["termination"] as? [String: Any]
    var reason: [String] = []
    if let namespace = termination?["namespace"] as? String { reason.append(namespace) }
    if let indicator = termination?["indicator"] as? String { reason.append(indicator) }
    if let code = termination?["code"] as? Int { reason.append("(code \(code))") }
    var messages: [String] = []
    if let asi = body["asi"] as? [String: Any] {
      for library in asi.keys.sorted() {
        messages += (asi[library] as? [String] ?? [])
      }
    }
    return CrashReport(
      url: url, exceptionType: exception?["type"] as? String,
      signal: exception?["signal"] as? String,
      terminationReason: reason.isEmpty ? nil : reason.joined(separator: " "),
      messages: messages)
  }
}
