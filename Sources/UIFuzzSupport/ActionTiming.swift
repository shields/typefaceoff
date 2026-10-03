import Foundation

public enum QuiescenceResult: String, Codable, Sendable {
  case settled, nextActionStarted, timeout, appExited
}

public struct ActionTiming: Codable, Equatable, Sendable {
  public var execution: String
  public var index: Int
  public var kind: FuzzAction.Kind
  public var target: String?
  public var resolutionStart: TimeInterval
  public var resolutionEnd: TimeInterval?
  public var dispatchStart: TimeInterval?
  public var dispatchReturn: TimeInterval?
  public var quiescentAt: TimeInterval?
  public var endedAt: TimeInterval
  public var result: QuiescenceResult
  public var maximumHeartbeatGap: TimeInterval = 0
  public var pendingAtDispatchReturn: [String: Int]?
  public var pendingAtSettlement: [String: Int]?
  public var pendingAtEnd: [String: Int] = [:]
  public var failure: String?

  public init(execution: String, index: Int, action: FuzzAction, start: TimeInterval) {
    self.execution = execution
    self.index = index
    kind = action.kind
    target = action.target
    resolutionStart = start
    endedAt = start
    result = .timeout
  }

  public var latencyMilliseconds: Double? {
    quiescentAt.map { ($0 - resolutionStart) * 1000 }
  }
}

public enum ActionQuiescence {
  public static let quietSeconds: TimeInterval = 0.2

  public static func settled(_ summary: TelemetrySummary, since: TimeInterval) -> Bool {
    guard let heartbeat = summary.lastHeartbeat, summary.pendingWork == 0 else { return false }
    return heartbeat - max(since, summary.lastActivity ?? since) >= quietSeconds
  }

  public static func measure(_ attempts: [ActionTiming], telemetry: String) -> [ActionTiming] {
    let events = telemetry.split(separator: "\n").compactMap { line -> (TimeInterval, Data)? in
      let data = Data(line.utf8)
      guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let uptime = event["uptime"] as? TimeInterval
      else { return nil }
      return (uptime, data)
    }
    var cursor = 0
    var summary = TelemetrySummary()
    return attempts.map { attempt in
      var timing = attempt
      while cursor < events.count && events[cursor].0 < timing.resolutionStart {
        summary.ingest(events[cursor].1)
        cursor += 1
      }
      var previousHeartbeat = summary.lastHeartbeat ?? timing.resolutionStart
      let responseStart = timing.dispatchReturn ?? timing.resolutionEnd ?? timing.endedAt
      while cursor < events.count && events[cursor].0 <= timing.endedAt {
        let (uptime, data) = events[cursor]
        if let returned = timing.dispatchReturn, uptime > returned,
          timing.pendingAtDispatchReturn == nil
        {
          timing.pendingAtDispatchReturn = summary.openWorkKinds
        }
        summary.ingest(data)
        cursor += 1
        guard timing.quiescentAt == nil else { continue }
        if let heartbeat = summary.lastHeartbeat, heartbeat > previousHeartbeat {
          timing.maximumHeartbeatGap = max(
            timing.maximumHeartbeatGap, heartbeat - max(previousHeartbeat, timing.resolutionStart))
          previousHeartbeat = heartbeat
        }
        if uptime >= responseStart, settled(summary, since: responseStart) {
          timing.quiescentAt = summary.lastHeartbeat
          timing.pendingAtSettlement = summary.openWorkKinds
          timing.result = .settled
        }
      }
      if timing.dispatchReturn != nil && timing.pendingAtDispatchReturn == nil {
        timing.pendingAtDispatchReturn = summary.openWorkKinds
      }
      if let settledAt = timing.quiescentAt {
        timing.endedAt = settledAt
        timing.pendingAtEnd = timing.pendingAtSettlement!
      } else {
        timing.maximumHeartbeatGap = max(
          timing.maximumHeartbeatGap,
          timing.endedAt - max(previousHeartbeat, timing.resolutionStart))
        timing.pendingAtEnd = summary.openWorkKinds
      }
      return timing
    }
  }
}
