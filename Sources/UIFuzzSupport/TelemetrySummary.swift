import Foundation

public struct TelemetrySummary: Equatable, Sendable {
  public var events = 0
  public var lastHeartbeat: TimeInterval?
  /// Uptime of the last event that is neither a heartbeat nor the launch marker.
  public var lastActivity: TimeInterval?
  public var maximumHeartbeatGap: TimeInterval = 0
  /// Work spans that have begun and not ended, as span id to kind.
  public var openWork: [String: String] = [:]
  /// The last snapshot event as sorted-keys JSON.
  public var latestSnapshot: String?
  public var correctnessFailures: [String] = []

  public init() {}

  public var pendingWork: Int { openWork.count }

  public var openWorkKinds: [String: Int] {
    openWork.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
  }

  /// `none`, or the open kinds in name order such as `feature-preview×1, ranking×2`.
  public var pendingSummary: String {
    let kinds = openWorkKinds
    guard !kinds.isEmpty else { return "none" }
    return kinds.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
  }

  /// A missing file is an empty summary; the caller reports missing telemetry itself.
  public static func read(_ url: URL) -> TelemetrySummary {
    guard let data = try? Data(contentsOf: url) else { return TelemetrySummary() }
    return parse(String(decoding: data, as: UTF8.self))
  }

  /// Unparsable lines are skipped, and a line ends only at a line feed.
  public static func parse(_ text: String) -> TelemetrySummary {
    var summary = TelemetrySummary()
    for line in text.utf8.split(separator: 0x0A) { summary.ingest(Data(line)) }
    return summary
  }

  /// True when the app has been quiet for `quiescence` seconds since `since`: it has emitted
  /// events, no work span is open, its main thread has run a turn after `since`, and its last
  /// non-heartbeat event is at least half of `quiescence` old.
  public func isIdle(since: TimeInterval, now: TimeInterval, quiescence: TimeInterval) -> Bool {
    guard
      events > 0 && pendingWork == 0 && (lastHeartbeat ?? -.infinity) >= since
        && now - since >= quiescence
    else { return false }
    return now - (lastActivity ?? -.infinity) >= quiescence / 2
  }

  mutating func ingest(_ line: Data) {
    guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    else { return }
    events += 1
    let kind = event["event"] as? String
    let uptime = event["uptime"] as? TimeInterval
    if kind != "heartbeat" && kind != "launch", let uptime { lastActivity = uptime }
    switch kind {
    case "heartbeat":
      if let uptime {
        if let previous = lastHeartbeat {
          maximumHeartbeatGap = max(maximumHeartbeatGap, uptime - previous)
        }
        lastHeartbeat = uptime
      }
    case "work-begin":
      openWork[event["id"] as? String ?? "unidentified-\(events)"] =
        event["kind"] as? String ?? "unknown"
    case "work-end":
      if let id = event["id"] as? String { openWork[id] = nil }
    case "snapshot":
      latestSnapshot = (try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]))
        .map { String(decoding: $0, as: UTF8.self) }
    case "invariant":
      if let detail = event["detail"] as? String { correctnessFailures.append(detail) }
    default: break
    }
  }
}

/// Follows a telemetry file that grows by whole lines, parsing only the bytes added since the
/// last refresh. The file is append-only.
public struct TelemetryTail: Sendable {
  public private(set) var summary = TelemetrySummary()
  /// Bytes taken from the file so far, including a line whose end has not arrived.
  public private(set) var offset = 0
  private var partial = Data()

  public init() {}

  /// `read` returns the file's bytes from the given offset to its end, or nothing.
  public mutating func refresh(read: (_ offset: Int) -> Data) -> TelemetrySummary {
    let bytes = read(offset)
    offset += bytes.count
    partial.append(bytes)
    if let end = partial.lastIndex(of: 0x0A) {
      for line in partial[..<end].split(separator: 0x0A) { summary.ingest(Data(line)) }
      partial.removeSubrange(...end)
    }
    return summary
  }
}

public enum TelemetryFile {
  public static func bytes(at url: URL, from offset: Int) -> Data {
    let handle = try? FileHandle(forReadingFrom: url)
    defer { try? handle?.close() }
    guard let handle, (try? handle.seek(toOffset: UInt64(offset))) != nil else { return Data() }
    return (try? handle.readToEnd()) ?? Data()
  }
}
