import Foundation
import Testing

@testable import UIFuzzSupport

enum TelemetryLines {
  static func line(
    _ event: String, at uptime: TimeInterval? = nil, _ fields: [String: Any] = [:]
  ) -> String {
    var object = fields
    object["event"] = event
    if let uptime { object["uptime"] = uptime }
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
  }

  static func text(_ lines: String...) -> String {
    lines.map { $0 + "\n" }.joined()
  }

  static func begin(_ id: String?, _ kind: String?, at uptime: TimeInterval) -> String {
    var fields: [String: Any] = [:]
    if let id { fields["id"] = id }
    if let kind { fields["kind"] = kind }
    return line("work-begin", at: uptime, fields)
  }

  static func end(_ id: String?, at uptime: TimeInterval) -> String {
    line("work-end", at: uptime, id.map { ["id": $0] } ?? [:])
  }
}

@Suite struct TelemetrySummaryTests {
  typealias Lines = TelemetryLines

  func parse(_ lines: String...) -> TelemetrySummary {
    TelemetrySummary.parse(lines.map { $0 + "\n" }.joined())
  }

  func withTemporaryFile<T>(_ contents: Data, _ body: (URL) throws -> T) throws -> T {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "telemetry-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    try contents.write(to: url)
    return try body(url)
  }

  @Test func emptyTextIsAnEmptySummary() {
    let summary = TelemetrySummary.parse("")
    #expect(summary == TelemetrySummary())
    #expect(summary.events == 0)
    #expect(summary.lastHeartbeat == nil)
    #expect(summary.lastActivity == nil)
    #expect(summary.maximumHeartbeatGap == 0)
    #expect(summary.pendingWork == 0)
    #expect(summary.latestSnapshot == nil)
    #expect(summary.correctnessFailures.isEmpty)
  }

  @Test func heartbeatsTrackTheLatestAndTheLargestGap() {
    let summary = parse(
      Lines.line("heartbeat", at: 1), Lines.line("heartbeat", at: 1.25),
      Lines.line("heartbeat", at: 2), Lines.line("heartbeat", at: 2.25))
    #expect(summary.events == 4)
    #expect(summary.lastHeartbeat == 2.25)
    #expect(summary.maximumHeartbeatGap == 0.75)
  }

  @Test func aSingleHeartbeatHasNoGap() {
    let summary = parse(Lines.line("heartbeat", at: 5))
    #expect(summary.lastHeartbeat == 5)
    #expect(summary.maximumHeartbeatGap == 0)
  }

  @Test func aHeartbeatWithoutAnUptimeCountsAsAnEventOnly() {
    let summary = parse(Lines.line("heartbeat"), Lines.line("heartbeat", at: 3))
    #expect(summary.events == 2)
    #expect(summary.lastHeartbeat == 3)
    #expect(summary.maximumHeartbeatGap == 0)
  }

  @Test func workSpansOpenAndCloseById() {
    let summary = parse(
      Lines.begin("a", "ranking", at: 1), Lines.begin("b", "feature-preview", at: 2),
      Lines.end("a", at: 3))
    #expect(summary.openWork == ["b": "feature-preview"])
    #expect(summary.pendingWork == 1)
    #expect(summary.events == 3)
  }

  @Test func anEndWithAnUnknownIdCannotCancelAnotherSpan() {
    let summary = parse(Lines.begin("a", "ranking", at: 1), Lines.end("zzz", at: 2))
    #expect(summary.openWork == ["a": "ranking"])
  }

  @Test func anEndBeforeItsBeginIsIgnored() {
    let summary = parse(Lines.end("a", at: 1), Lines.begin("a", "ranking", at: 2))
    #expect(summary.pendingWork == 1)
  }

  @Test func aBeginWithoutAnIdStillCountsAndAnEndWithoutOneIsIgnored() {
    let summary = parse(
      Lines.begin(nil, "ranking", at: 1), Lines.begin(nil, "ranking", at: 2),
      Lines.end(nil, at: 3))
    #expect(summary.pendingWork == 2)
    #expect(summary.openWorkKinds == ["ranking": 2])
  }

  @Test func aBeginWithoutAKindIsUnknownWork() {
    let summary = parse(Lines.begin("a", nil, at: 1))
    #expect(summary.openWork == ["a": "unknown"])
    #expect(summary.pendingSummary == "unknown×1")
  }

  @Test func aDuplicateBeginIdIsOneSpanClosedByOneEnd() {
    let summary = parse(
      Lines.begin("a", "ranking", at: 1), Lines.begin("a", "feature-preview", at: 2))
    #expect(summary.pendingWork == 1)
    #expect(summary.openWork == ["a": "feature-preview"])
    let closed = parse(
      Lines.begin("a", "ranking", at: 1), Lines.begin("a", "ranking", at: 2),
      Lines.end("a", at: 3))
    #expect(closed.pendingWork == 0)
  }

  @Test func pendingWorkIsTheNumberOfOpenSpans() {
    let summary = parse(
      Lines.begin("a", "ranking", at: 1), Lines.begin("b", "ranking", at: 2),
      Lines.begin("c", "character-search", at: 3))
    #expect(summary.pendingWork == summary.openWork.count)
    #expect(summary.pendingWork == 3)
  }

  @Test func openWorkKindsAndPendingSummary() {
    #expect(TelemetrySummary().openWorkKinds.isEmpty)
    #expect(TelemetrySummary().pendingSummary == "none")
    let summary = parse(
      Lines.begin("a", "ranking", at: 1), Lines.begin("b", "ranking", at: 2),
      Lines.begin("c", "feature-preview", at: 3))
    #expect(summary.openWorkKinds == ["ranking": 2, "feature-preview": 1])
    #expect(summary.pendingSummary == "feature-preview×1, ranking×2")
    let closed = parse(Lines.begin("a", "ranking", at: 1), Lines.end("a", at: 2))
    #expect(closed.pendingSummary == "none")
  }

  @Test func theLatestSnapshotIsSortedKeysJSON() {
    let older = #"{"event":"snapshot","uptime":1.5,"window":"W1","a":"Old"}"#
    let latest =
      #"{"window":"W2","uptime":3.5,"textUTF16":12,"locked":false,"event":"snapshot","aSize":24.5,"aFeatures":["liga"],"a":"Times-Roman"}"#
    let summary = parse(older, Lines.line("heartbeat", at: 2), latest)
    #expect(
      summary.latestSnapshot
        == #"{"a":"Times-Roman","aFeatures":["liga"],"aSize":24.5,"event":"snapshot","locked":false,"textUTF16":12,"uptime":3.5,"window":"W2"}"#
    )
    #expect(
      parse(older).latestSnapshot == #"{"a":"Old","event":"snapshot","uptime":1.5,"window":"W1"}"#)
    #expect(parse(Lines.line("heartbeat", at: 2)).latestSnapshot == nil)
  }

  @Test func invariantFailuresKeepTheirDetail() {
    let summary = parse(
      Lines.line("invariant", at: 1, ["detail": "Tracking escaped its native range"]),
      Lines.line("invariant", at: 2), Lines.line("invariant", at: 3, ["detail": 7]),
      Lines.line("invariant", at: 4, ["detail": "Point size escaped its native range"]))
    #expect(
      summary.correctnessFailures == [
        "Tracking escaped its native range", "Point size escaped its native range",
      ])
    #expect(summary.events == 4)
  }

  @Test func unparsableLinesAreSkipped() {
    let text =
      "not json\n\n[1, 2]\n\"text\"\n{\"event\":\n"
      + Lines.text(Lines.line("heartbeat", at: 1), Lines.line("render", at: 2, ["kind": "glyph"]))
    let summary = TelemetrySummary.parse(text)
    #expect(summary.events == 2)
    #expect(summary.lastHeartbeat == 1)
  }

  @Test func anObjectWithoutAnEventKindCountsAsActivity() {
    let summary = TelemetrySummary.parse(#"{"uptime":4.5}"# + "\n")
    #expect(summary.events == 1)
    #expect(summary.lastActivity == 4.5)
  }

  @Test func aFinalLineWithoutALineFeedStillParses() {
    let summary = TelemetrySummary.parse(Lines.line("heartbeat", at: 1))
    #expect(summary.events == 1)
  }

  @Test func activityExcludesHeartbeatsAndTheLaunchMarker() {
    let quiet = parse(Lines.line("launch", at: 1), Lines.line("heartbeat", at: 2))
    #expect(quiet.events == 2)
    #expect(quiet.lastActivity == nil)
    let busy = parse(
      Lines.line("launch", at: 1), Lines.line("snapshot", at: 2, ["window": "W"]),
      Lines.line("render", at: 3, ["kind": "specimen"]),
      Lines.line("glyph-geometry", at: 4, ["view": "a"]), Lines.begin("a", "ranking", at: 5),
      Lines.end("a", at: 6), Lines.line("invariant", at: 7, ["detail": "x"]),
      Lines.line("heartbeat", at: 8))
    #expect(busy.lastActivity == 7)
    #expect(busy.lastHeartbeat == 8)
  }

  @Test func anEventWithoutAnUptimeLeavesTheActivityTimeAlone() {
    let summary = parse(Lines.line("render", at: 2), Lines.line("render"))
    #expect(summary.events == 2)
    #expect(summary.lastActivity == 2)
  }

  @Test func eventsCountEveryParsedLine() {
    let summary = parse(
      Lines.line("launch", at: 1), Lines.line("heartbeat", at: 2), Lines.line("mystery", at: 3))
    #expect(summary.events == 3)
  }

  @Test func readingAMissingFileGivesAnEmptySummary() {
    let missing = FileManager.default.temporaryDirectory.appending(
      path: "telemetry-\(UUID().uuidString).jsonl")
    #expect(TelemetrySummary.read(missing) == TelemetrySummary())
  }

  @Test func readParsesAFile() throws {
    let text = Lines.text(
      Lines.line("launch", at: 1), Lines.line("heartbeat", at: 2), Lines.line("heartbeat", at: 2.5))
    try withTemporaryFile(Data(text.utf8)) { url in
      let summary = TelemetrySummary.read(url)
      #expect(summary == TelemetrySummary.parse(text))
      #expect(summary.events == 3)
      #expect(summary.maximumHeartbeatGap == 0.5)
    }
  }

  @Test func aTornMultibyteTailStillParsesTheEarlierLines() throws {
    var bytes = Data(
      Lines.text(
        Lines.line("heartbeat", at: 1),
        Lines.line("invariant", at: 2, ["detail": "Glyph navigation moved the baseline"])
      ).utf8)
    bytes.append(contentsOf: Array(#"{"event":"invariant","detail":"caf"#.utf8) + [0xC3])
    try withTemporaryFile(bytes) { url in
      let summary = TelemetrySummary.read(url)
      #expect(summary.events == 2)
      #expect(summary.correctnessFailures == ["Glyph navigation moved the baseline"])
    }
  }

  @Test func multibyteTextSurvivesParsing() {
    let summary = parse(Lines.line("invariant", at: 1, ["detail": "Ligature ﬁ × café"]))
    #expect(summary.correctnessFailures == ["Ligature ﬁ × café"])
  }

  struct LegacyState {
    var lastHeartbeat: TimeInterval?
    var maximumHeartbeatGap: TimeInterval = 0
    var pendingWork = 0
    var latestSnapshot: [String: Any]?
    var correctnessFailures: [String] = []
    var events = 0

    init(text: String) {
      for line in text.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
          let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }
        events += 1
        switch event["event"] as? String {
        case "heartbeat":
          if let uptime = event["uptime"] as? TimeInterval {
            if let previous = lastHeartbeat {
              maximumHeartbeatGap = max(maximumHeartbeatGap, uptime - previous)
            }
            lastHeartbeat = uptime
          }
        case "work-begin": pendingWork += 1
        case "work-end": pendingWork = max(0, pendingWork - 1)
        case "snapshot": latestSnapshot = event
        case "invariant":
          if let detail = event["detail"] as? String { correctnessFailures.append(detail) }
        default: break
        }
      }
    }
  }

  func randomTelemetry(seed: UInt64, count: Int) -> String {
    var random = SplitMix64(seed: seed)
    var open: [String] = []
    var uptime = 1.0
    var lines: [String] = []
    for index in 0..<count {
      uptime += Double(random.next() % 40) / 8
      switch random.next() % 8 {
      case 0:
        let id = "span-\(index)"
        open.append(id)
        lines.append(Lines.begin(id, ["ranking", "feature-preview"][index % 2], at: uptime))
      case 1 where !open.isEmpty:
        let id = open.remove(at: Int(random.next() % UInt64(open.count)))
        lines.append(Lines.end(id, at: uptime))
      case 2:
        lines.append(
          Lines.line(
            "snapshot", at: uptime,
            ["window": "W\(index % 3)", "aSize": Double(index) / 4, "flag": index % 2 == 0]))
      case 3:
        lines.append(Lines.line("invariant", at: uptime, ["detail": "Failure \(index)"]))
      case 4:
        lines.append(Lines.line("render", at: uptime, ["kind": "glyph"]))
      default:
        lines.append(Lines.line("heartbeat", at: uptime))
      }
    }
    return lines.map { $0 + "\n" }.joined()
  }

  @Test func matchesTheLegacyParserOnBalancedTelemetry() {
    for seed in 0..<40 {
      let text = randomTelemetry(seed: UInt64(seed), count: 250)
      let legacy = LegacyState(text: text)
      let summary = TelemetrySummary.parse(text)
      #expect(summary.events == legacy.events)
      #expect(summary.lastHeartbeat == legacy.lastHeartbeat)
      #expect(summary.maximumHeartbeatGap == legacy.maximumHeartbeatGap)
      #expect(summary.pendingWork == legacy.pendingWork)
      #expect(summary.correctnessFailures == legacy.correctnessFailures)
      let snapshot = legacy.latestSnapshot.map {
        String(
          decoding: try! JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]),
          as: UTF8.self)
      }
      #expect(summary.latestSnapshot == snapshot)
    }
  }
}

@Suite struct TelemetryTailTests {
  typealias Lines = TelemetryLines

  final class Feed {
    var bytes: Data
    private(set) var offsets: [Int] = []

    init(_ text: String) { bytes = Data(text.utf8) }

    func chunk(_ size: Int) -> (Int) -> Data {
      { offset in
        self.offsets.append(offset)
        return Data(self.bytes.dropFirst(offset).prefix(size))
      }
    }
  }

  var sample: String {
    Lines.text(
      Lines.line("launch", at: 1), Lines.line("heartbeat", at: 2),
      Lines.begin("a", "ranking", at: 2.25), Lines.line("heartbeat", at: 2.5),
      Lines.line("invariant", at: 2.75, ["detail": "Ligature ﬁ × café"]),
      Lines.line("snapshot", at: 3, ["window": "W", "aSize": 24.5]), Lines.end("a", at: 3.25),
      Lines.line("heartbeat", at: 3.5))
  }

  @Test(arguments: [1, 2, 3, 7, 64, 100_000])
  func anyChunkingParsesLikeTheWholeFile(size: Int) {
    let feed = Feed(sample)
    var tail = TelemetryTail()
    var last = TelemetrySummary()
    while tail.offset < feed.bytes.count { last = tail.refresh(read: feed.chunk(size)) }
    #expect(last == TelemetrySummary.parse(sample))
    #expect(tail.summary == last)
    #expect(tail.offset == feed.bytes.count)
    #expect(last.events == 8)
    #expect(feed.offsets.first == 0)
    #expect(feed.offsets == feed.offsets.sorted())
  }

  @Test func anEmptyReadChangesNothing() {
    var tail = TelemetryTail()
    #expect(tail.refresh(read: { _ in Data() }) == TelemetrySummary())
    #expect(tail.offset == 0)
  }

  @Test func aLineCountsOnlyOnceItsLineFeedArrives() {
    let line = Lines.line("heartbeat", at: 4)
    let feed = Feed(line)
    var tail = TelemetryTail()
    #expect(tail.refresh(read: feed.chunk(1000)).events == 0)
    #expect(tail.offset == line.utf8.count)
    feed.bytes.append(0x0A)
    let summary = tail.refresh(read: feed.chunk(1000))
    #expect(summary.events == 1)
    #expect(summary.lastHeartbeat == 4)
  }

  @Test func eachRefreshAsksOnlyForWhatItHasNotSeen() {
    let feed = Feed(Lines.text(Lines.line("heartbeat", at: 1)))
    var tail = TelemetryTail()
    _ = tail.refresh(read: feed.chunk(1000))
    let firstEnd = feed.bytes.count
    _ = tail.refresh(read: feed.chunk(1000))
    feed.bytes.append(Data(Lines.text(Lines.line("heartbeat", at: 2)).utf8))
    let summary = tail.refresh(read: feed.chunk(1000))
    #expect(feed.offsets == [0, firstEnd, firstEnd])
    #expect(summary.events == 2)
    #expect(summary.maximumHeartbeatGap == 1)
  }

  @Test func blankAndBrokenLinesInTheTailAreSkipped() {
    let feed = Feed("garbage\n\n" + Lines.text(Lines.line("render", at: 1)))
    var tail = TelemetryTail()
    let summary = tail.refresh(read: feed.chunk(1000))
    #expect(summary.events == 1)
    #expect(summary.lastActivity == 1)
  }
}

@Suite struct TelemetryFileTests {
  func withTemporaryFile(_ contents: Data, _ body: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "telemetry-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    try contents.write(to: url)
    try body(url)
  }

  @Test func aMissingFileHasNoBytes() {
    let missing = FileManager.default.temporaryDirectory.appending(
      path: "telemetry-\(UUID().uuidString).jsonl")
    #expect(TelemetryFile.bytes(at: missing, from: 0).isEmpty)
  }

  @Test func bytesRunFromTheOffsetToTheEnd() throws {
    try withTemporaryFile(Data("0123456789".utf8)) { url in
      #expect(TelemetryFile.bytes(at: url, from: 0) == Data("0123456789".utf8))
      #expect(TelemetryFile.bytes(at: url, from: 4) == Data("456789".utf8))
      #expect(TelemetryFile.bytes(at: url, from: 10).isEmpty)
      #expect(TelemetryFile.bytes(at: url, from: 25).isEmpty)
    }
  }

  @Test func anEmptyFileHasNoBytes() throws {
    try withTemporaryFile(Data()) { url in
      #expect(TelemetryFile.bytes(at: url, from: 0).isEmpty)
    }
  }

  @Test func aGrowingFileYieldsOnlyItsNewBytes() throws {
    try withTemporaryFile(Data("first\n".utf8)) { url in
      let first = TelemetryFile.bytes(at: url, from: 0)
      let handle = try FileHandle(forWritingTo: url)
      try handle.seekToEnd()
      try handle.write(contentsOf: Data("second\n".utf8))
      try handle.close()
      #expect(TelemetryFile.bytes(at: url, from: first.count) == Data("second\n".utf8))
    }
  }

  @Test func aDirectoryHasNoBytes() {
    #expect(TelemetryFile.bytes(at: FileManager.default.temporaryDirectory, from: 0).isEmpty)
  }
}
