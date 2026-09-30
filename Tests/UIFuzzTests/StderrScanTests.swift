import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct StderrScanTests {
  private let warning =
    "WARNING: Application dropped a request in its fixture delegate. This warning will become an assert in the future."

  private func nslog(_ message: String, time: String, pid: Int, thread: Int) -> String {
    "2026-09-29 \(time) TypefaceOff[\(pid):\(thread)] \(message)"
  }

  private func temporaryLog(_ contents: Data?) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "stderr-scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "stderr.log")
    if let contents { try contents.write(to: url) }
    return url
  }

  @Test func emptyAndWhitespaceOnlyTextIsSilence() {
    #expect(StderrScan.finding(in: "") == nil)
    #expect(StderrScan.finding(in: " \n\t\r\n  \n") == nil)
  }

  @Test func aPrefixWithNoMessageIsSilence() {
    #expect(StderrScan.finding(in: nslog("", time: "18:25:46.414", pid: 1, thread: 2)) == nil)
  }

  @Test func oneLineGivesTheExactSignatureAndDetail() throws {
    let text = nslog(warning, time: "18:25:46.414", pid: 21700, thread: 4_473_054) + "\n"
    let finding = try #require(StderrScan.finding(in: text))
    #expect(finding.kind == .correctness)
    #expect(finding.signature == "app-stderr: " + warning)
    #expect(finding.detail == "The app wrote 1 line to stderr, 1 distinct.\n1x " + warning)
  }

  @Test func theSameMessageAcrossTimestampsAndPidsIsOneEntryWithACount() throws {
    let text = [
      nslog(warning, time: "18:25:46.414", pid: 21700, thread: 4_473_054),
      nslog(warning, time: "18:25:48.746", pid: 21700, thread: 4_473_054),
      nslog(warning, time: "09:01:02.003", pid: 99, thread: 0x1a2b),
    ].joined(separator: "\n")
    let finding = try #require(StderrScan.finding(in: text))
    #expect(finding.signature == "app-stderr: " + warning)
    #expect(finding.detail == "The app wrote 3 lines to stderr, 1 distinct.\n3x " + warning)
  }

  @Test func theSignatureIgnoresWhichRunWroteTheLine() throws {
    let first = StderrScan.finding(
      in: nslog(warning, time: "18:25:46.414", pid: 1, thread: 2))
    let second = StderrScan.finding(
      in: nslog(warning, time: "07:00:00.001", pid: 800, thread: 9) + "\n")
    #expect(first?.signature == second?.signature)
  }

  @Test func aTimezoneOffsetInThePrefixIsStripped() throws {
    let finding = try #require(
      StderrScan.finding(
        in: "2026-09-29 18:25:46.414+0100 TypefaceOff[1:2] hello"))
    #expect(finding.signature == "app-stderr: hello")
  }

  @Test func aMixKeepsFirstSeenOrderAndTheFirstMessageNamesTheSignature() throws {
    let text = [
      "Fatal error: something",
      nslog("second", time: "18:25:46.414", pid: 1, thread: 2),
      "",
      "Fatal error: something",
      "  second  ",
      "Fatal error: something",
    ].joined(separator: "\n")
    let finding = try #require(StderrScan.finding(in: text))
    #expect(finding.signature == "app-stderr: Fatal error: something")
    #expect(
      finding.detail
        == "The app wrote 5 lines to stderr, 2 distinct.\n3x Fatal error: something\n2x second"
    )
  }

  @Test func windowsLineEndingsCountOnce() throws {
    let finding = try #require(StderrScan.finding(in: "a\r\nb\r\na\r\n"))
    #expect(finding.detail == "The app wrote 3 lines to stderr, 2 distinct.\n2x a\n1x b")
  }

  @Test func aLineThatOnlyLooksLikeAPrefixIsKept() throws {
    let finding = try #require(StderrScan.finding(in: "2026-09-29 not a log prefix"))
    #expect(finding.signature == "app-stderr: 2026-09-29 not a log prefix")
  }

  @Test func onlyAHandfulOfDistinctLinesAreListed() throws {
    let text = (1...8).map { "message \($0)" }.joined(separator: "\n")
    let finding = try #require(StderrScan.finding(in: text))
    #expect(finding.signature == "app-stderr: message 1")
    let lines = finding.detail.split(separator: "\n").map(String.init)
    #expect(lines.first == "The app wrote 8 lines to stderr, 8 distinct.")
    #expect(lines.dropFirst().dropLast() == (1...5).map { "1x message \($0)" }[...])
    #expect(lines.last == "... and 3 more distinct lines.")
    #expect(lines.count == 1 + StderrScan.distinctLineLimit + 1)
  }

  @Test func exactlyAtTheLimitAddsNoOverflowLine() throws {
    let text = (1...StderrScan.distinctLineLimit).map { "m\($0)" }.joined(separator: "\n")
    let finding = try #require(StderrScan.finding(in: text))
    #expect(!finding.detail.contains("more distinct"))
  }

  @Test func aVeryLongLineIsClippedInTheSignatureAndTheDetail() throws {
    let long = String(repeating: "x", count: 100_000)
    let finding = try #require(StderrScan.finding(in: long))
    #expect(finding.signature == "app-stderr: " + String(repeating: "x", count: 200) + "...")
    let entry = try #require(finding.detail.split(separator: "\n").last)
    #expect(entry == "1x " + String(repeating: "x", count: 300) + "...")
  }

  @Test func aLineExactlyAtTheLengthCapIsNotClipped() throws {
    let text = String(repeating: "y", count: 200)
    let finding = try #require(StderrScan.finding(in: text))
    #expect(finding.signature == "app-stderr: " + text)
  }

  @Test func runawayLoggingStaysBounded() throws {
    let text = (0..<20_000).map { "line \($0) " + String(repeating: "z", count: 500) }
      .joined(separator: "\n")
    let finding = try #require(StderrScan.finding(in: text))
    #expect(finding.detail.count < 3_000)
  }

  @Test func allowedSubstringsAreNotEvidence() throws {
    let text = "benign noise here\nreal problem\nmore benign noise"
    let finding = try #require(StderrScan.finding(in: text, allowing: ["benign noise"]))
    #expect(finding.signature == "app-stderr: real problem")
    #expect(finding.detail == "The app wrote 1 line to stderr, 1 distinct.\n1x real problem")
    #expect(StderrScan.finding(in: "benign noise", allowing: ["benign noise"]) == nil)
  }

  @Test func theSwiftUIListReentrancyWarningIsNotEvidence() throws {
    let prefix = "2026-09-29 18:25:46.414 TypefaceOff[21700:4473054] "
    let warning =
      prefix + "WARNING: Application performed a reentrant operation in its NSTableView delegate. "
      + "This warning will become an assert in the future."
    #expect(StderrScan.finding(in: warning) == nil)
    #expect(StderrScan.finding(in: warning + "\n" + warning) == nil)
    let finding = try #require(StderrScan.finding(in: warning + "\nsomething else"))
    #expect(finding.signature == "app-stderr: something else")
  }

  @Test func truncationIsSaidInTheDetail() throws {
    let finding = try #require(StderrScan.finding(in: "x", truncated: true))
    #expect(
      finding.detail
        == "The app wrote 1 line to stderr, 1 distinct. Only the start of the log was scanned.\n1x x"
    )
  }

  @Test func anEmptyLogFileIsSilence() throws {
    let url = try temporaryLog(Data())
    #expect(try StderrScan.finding(logAt: url, absentIsEmpty: false) == nil)
  }

  @Test func aLogFileWithTheWarningGivesTheFinding() throws {
    let text = nslog(warning, time: "18:25:46.414", pid: 5, thread: 6) + "\n"
    let url = try temporaryLog(Data(text.utf8))
    let finding = try #require(try StderrScan.finding(logAt: url, absentIsEmpty: false))
    #expect(finding.signature == "app-stderr: " + warning)
  }

  @Test func aLogFileHonorsTheAllowlist() throws {
    let url = try temporaryLog(Data("noise\n".utf8))
    #expect(try StderrScan.finding(logAt: url, absentIsEmpty: false, allowing: ["noise"]) == nil)
  }

  @Test func aLogFileBeyondTheReadLimitIsScannedFromItsStart() throws {
    let url = try temporaryLog(Data("first\nsecond\nthird\n".utf8))
    let finding = try #require(
      try StderrScan.finding(logAt: url, absentIsEmpty: false, readLimit: 8))
    #expect(finding.signature == "app-stderr: first")
    #expect(finding.detail.contains("Only the start of the log was scanned."))
    #expect(!finding.detail.contains("third"))
  }

  @Test func aLogFileExactlyAtTheReadLimitIsNotTruncated() throws {
    let url = try temporaryLog(Data("abcd".utf8))
    let finding = try #require(
      try StderrScan.finding(logAt: url, absentIsEmpty: false, readLimit: 4))
    #expect(!finding.detail.contains("Only the start"))
  }

  @Test func invalidUTF8StaysVisible() throws {
    let url = try temporaryLog(Data([0x61, 0xff, 0x62, 0x0a]))
    let finding = try #require(try StderrScan.finding(logAt: url, absentIsEmpty: false))
    #expect(finding.signature == "app-stderr: a\u{fffd}b")
  }

  @Test func aMissingLogIsSilenceOnlyWhenTheCallerSaysSo() throws {
    let url = try temporaryLog(nil)
    #expect(try StderrScan.finding(logAt: url, absentIsEmpty: true) == nil)
    #expect(throws: StderrLogError(url: url)) {
      try StderrScan.finding(logAt: url, absentIsEmpty: false)
    }
    #expect(StderrLogError(url: url).errorDescription == StderrLogError(url: url).description)
    #expect(StderrLogError(url: url).description.contains(url.path))
  }

  @Test func anUnreadableLogIsAnError() throws {
    let url = try temporaryLog(Data("x\n".utf8))
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) {
      try StderrScan.finding(logAt: url, absentIsEmpty: false)
    }
  }
}
