import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct CrashReportsTests {
  private static let header =
    #"{"app_name":"TypefaceOff","bug_type":"309","name":"TypefaceOff"}"#

  private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "crash-reports-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @discardableResult
  private func writeReport(
    _ name: String, in directory: URL, pid: Int = 4242, process: String = "TypefaceOff",
    modified: Date = Date(),
    extra: String = """
    "exception" : {"codes":"0x1","type":"EXC_BREAKPOINT","signal":"SIGTRAP"},
    "termination" : {"flags":0,"code":5,"namespace":"SIGNAL","indicator":"Trace\\/BPT trap: 5"},
    "asi" : {"libswiftCore.dylib":["Fatal error: index out of range"]},
    """
  ) throws -> URL {
    let url = directory.appending(path: name)
    let body = """
      {
        "uptime" : 1200000,
        \(extra)
        "pid" : \(pid),
        "procName" : "\(process)"
      }
      """
    try Data((Self.header + "\n" + body).utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    return url
  }

  @Test func findsTheReportForThePidAndReadsItsReason() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try writeReport("TypefaceOff-2026-09-29-101010.ips", in: directory)
    try writeReport("TypefaceOff-2026-09-29-101011.ips", in: directory, pid: 99)
    try writeReport("Other-2026-09-29-101012.ips", in: directory, process: "Other")

    let result = try CrashReports.search(
      pid: 4242, processName: "TypefaceOff", directory: directory,
      since: Date(timeIntervalSinceNow: -60))
    let report = try #require(result.report)
    #expect(result.unreadable.isEmpty)
    #expect(report.url.lastPathComponent == "TypefaceOff-2026-09-29-101010.ips")
    #expect(
      report
        == CrashReport(
          url: report.url, exceptionType: "EXC_BREAKPOINT", signal: "SIGTRAP",
          terminationReason: "SIGNAL Trace/BPT trap: 5 (code 5)",
          messages: ["Fatal error: index out of range"]))
    #expect(
      report.summary
        == "Exception EXC_BREAKPOINT (SIGTRAP); termination SIGNAL Trace/BPT trap: 5 (code 5); "
        + "\"Fatal error: index out of range\"")
  }

  @Test func reportsOlderThanTheWindowBelongToAnEarlierProcessWithTheSamePid() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try writeReport(
      "TypefaceOff-old.ips", in: directory, modified: Date(timeIntervalSinceNow: -3600))
    let result = try CrashReports.search(
      pid: 4242, processName: "TypefaceOff", directory: directory,
      since: Date(timeIntervalSinceNow: -60))
    #expect(result == CrashReportSearch(report: nil, unreadable: []))
  }

  @Test func newestMatchingReportWins() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try writeReport(
      "TypefaceOff-first.ips", in: directory, modified: Date(timeIntervalSinceNow: -10))
    try writeReport("TypefaceOff-second.ips", in: directory)
    let result = try CrashReports.search(
      pid: 4242, processName: "TypefaceOff", directory: directory,
      since: Date(timeIntervalSinceNow: -60))
    #expect(result.report?.url.lastPathComponent == "TypefaceOff-second.ips")
  }

  @Test func reportsWithoutReasonFieldsStillSummarize() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try writeReport("TypefaceOff-bare.ips", in: directory, extra: "")
    let report = try #require(
      try CrashReports.search(
        pid: 4242, processName: "TypefaceOff", directory: directory,
        since: Date(timeIntervalSinceNow: -60)
      ).report)
    #expect(report.exceptionType == nil)
    #expect(report.terminationReason == nil)
    #expect(report.messages.isEmpty)
    #expect(report.summary == "The report names no exception or termination reason.")
  }

  @Test func summaryCapsTheNumberAndLengthOfMessages() {
    let long = String(repeating: "x", count: 400)
    let report = CrashReport(
      url: URL(fileURLWithPath: "/tmp/a.ips"), exceptionType: "EXC_CRASH",
      messages: [long] + (1...6).map { "m\($0)" })
    #expect(report.summary.contains("\"\(String(repeating: "x", count: 300))\""))
    #expect(!report.summary.contains(String(repeating: "x", count: 301)))
    #expect(report.summary.contains("m4"))
    #expect(!report.summary.contains("m5"))
  }

  @Test func messagesComeFromEveryLibraryInNameOrder() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try writeReport(
      "TypefaceOff-asi.ips", in: directory,
      extra: #""asi" : {"b.dylib":["two"],"a.dylib":["one"],"c.dylib":"not a list"},"#)
    let report = try #require(
      try CrashReports.search(
        pid: 4242, processName: "TypefaceOff", directory: directory,
        since: Date(timeIntervalSinceNow: -60)
      ).report)
    #expect(report.messages == ["one", "two"])
  }

  @Test func unparseableRecentReportsAreNamedNotSkippedSilently() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("{\"app_name\":\"TypefaceOff\"}".utf8).write(
      to: directory.appending(path: "TypefaceOff-header-only.ips"))
    try Data("{}\n[1, 2]".utf8).write(to: directory.appending(path: "TypefaceOff-array.ips"))
    try Data("not a report".utf8).write(to: directory.appending(path: "notes.txt"))
    let result = try CrashReports.search(
      pid: 4242, processName: "TypefaceOff", directory: directory,
      since: Date(timeIntervalSinceNow: -60))
    #expect(result.report == nil)
    #expect(result.unreadable.sorted() == ["TypefaceOff-array.ips", "TypefaceOff-header-only.ips"])
  }

  @Test func aGuestThatNeverCrashedHasNoReportDirectory() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "crash-reports-missing-\(UUID().uuidString)")
    let result = try CrashReports.search(
      pid: 4242, processName: "TypefaceOff", directory: directory, since: .distantPast)
    #expect(result == CrashReportSearch(report: nil, unreadable: []))
  }

  @Test func aDirectoryThatCannotBeListedIsAnError() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "not-a-directory")
    try Data().write(to: file)
    #expect(throws: (any Error).self) {
      try CrashReports.search(
        pid: 4242, processName: "TypefaceOff", directory: file, since: .distantPast)
    }
  }

  @Test func waitPollsUntilTheReportAppears() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var now = 50.0
    var sleeps: [TimeInterval] = []
    let result = try CrashReports.waitForReport(
      pid: 4242, processName: "TypefaceOff", directory: directory,
      since: Date(timeIntervalSinceNow: -60), timeout: 5, pollInterval: 1,
      clock: { now },
      sleep: {
        sleeps.append($0)
        now += $0
        if sleeps.count == 2 {
          _ = try? writeReport("TypefaceOff-late.ips", in: directory)
        }
      })
    #expect(result.report?.url.lastPathComponent == "TypefaceOff-late.ips")
    #expect(sleeps == [1, 1])
  }

  @Test func waitGivesUpAtTheDeadlineWithItsLastSleepClamped() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var now = 0.0
    var sleeps: [TimeInterval] = []
    let result = try CrashReports.waitForReport(
      pid: 4242, processName: "TypefaceOff", directory: directory,
      since: Date(timeIntervalSinceNow: -60), timeout: 2.5, pollInterval: 1,
      clock: { now },
      sleep: {
        sleeps.append($0)
        now += $0
      })
    #expect(result.report == nil)
    #expect(sleeps == [1, 1, 0.5])
  }

  @Test func waitSearchesOnceEvenWithNoTimeToWait() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try writeReport("TypefaceOff-now.ips", in: directory)
    let result = try CrashReports.waitForReport(
      pid: 4242, processName: "TypefaceOff", directory: directory,
      since: Date(timeIntervalSinceNow: -60), timeout: 0, clock: { 0 },
      sleep: { _ in Issue.record("must not sleep") })
    #expect(result.report != nil)
  }

  @Test func captureCopiesTheReportIntoTheRunAndDescribesIt() throws {
    let directory = try makeDirectory()
    let run = try makeDirectory()
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: run)
    }
    try writeReport("TypefaceOff-crash.ips", in: directory)
    let note = CrashReports.capture(
      pid: 4242, processName: "TypefaceOff", since: Date(timeIntervalSinceNow: -60), into: run,
      directory: directory, timeout: 0, clock: { 0 }, sleep: { _ in })
    #expect(note.hasPrefix("Crash report TypefaceOff-crash.ips, copied into the run: Exception"))
    #expect(note.contains("EXC_BREAKPOINT (SIGTRAP)"))
    #expect(
      FileManager.default.fileExists(atPath: run.appending(path: "TypefaceOff-crash.ips").path))
  }

  @Test func captureSaysSoWhenNoReportAppears() throws {
    let directory = try makeDirectory()
    let run = try makeDirectory()
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: run)
    }
    let note = CrashReports.capture(
      pid: 4242, processName: "TypefaceOff", since: Date(timeIntervalSinceNow: -60), into: run,
      directory: directory, timeout: 0, clock: { 0 }, sleep: { _ in })
    #expect(
      note == "No crash report for pid 4242 appeared in \(directory.path) within 0 s.")
    #expect(try FileManager.default.contentsOfDirectory(atPath: run.path).isEmpty)

    try Data("junk".utf8).write(to: directory.appending(path: "TypefaceOff-junk.ips"))
    let withJunk = CrashReports.capture(
      pid: 4242, processName: "TypefaceOff", since: Date(timeIntervalSinceNow: -60), into: run,
      directory: directory, timeout: 0, clock: { 0 }, sleep: { _ in })
    #expect(withJunk.hasSuffix("Unparseable recent reports: TypefaceOff-junk.ips."))
  }

  @Test func captureReportsAFailureToSearch() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "not-a-directory")
    try Data().write(to: file)
    let note = CrashReports.capture(
      pid: 4242, processName: "TypefaceOff", since: .distantPast, into: directory,
      directory: file, timeout: 0, clock: { 0 }, sleep: { _ in })
    #expect(note.hasPrefix("Could not search \(file.path) for a crash report:"))
  }

  @Test func captureReportsAFailureToCopyAndStillDescribesTheReport() throws {
    let directory = try makeDirectory()
    let run = try makeDirectory()
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: run)
    }
    try writeReport("TypefaceOff-crash.ips", in: directory)
    try Data().write(to: run.appending(path: "TypefaceOff-crash.ips"))
    let note = CrashReports.capture(
      pid: 4242, processName: "TypefaceOff", since: Date(timeIntervalSinceNow: -60), into: run,
      directory: directory, timeout: 0, clock: { 0 }, sleep: { _ in })
    #expect(
      note.hasPrefix(
        "Crash report TypefaceOff-crash.ips was found but could not be copied into the run:"))
    #expect(
      note.hasSuffix(
        "Exception EXC_BREAKPOINT (SIGTRAP); termination SIGNAL Trace/BPT trap: 5 (code 5); \"Fatal error: index out of range\""
      ))
  }

  @Test func theRealClockBoundsTheWait() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let since = Date(timeIntervalSinceNow: -60)
    let started = ProcessInfo.processInfo.systemUptime
    let result = try CrashReports.waitForReport(
      pid: 4242, processName: "TypefaceOff", directory: directory, since: since, timeout: 0.05)
    #expect(result.report == nil)
    #expect(ProcessInfo.processInfo.systemUptime - started >= 0.05)

    let note = CrashReports.capture(
      pid: 4242, processName: "TypefaceOff", since: since, into: directory,
      directory: directory, timeout: 0.05)
    #expect(note.hasPrefix("No crash report for pid 4242"))
  }

  @Test func theDefaultDirectoryIsTheUsersDiagnosticReports() {
    #expect(
      CrashReports.defaultDirectory.path.hasSuffix("/Library/Logs/DiagnosticReports"))
    #expect(CrashReports.defaultTimeout == 10)
  }
}
