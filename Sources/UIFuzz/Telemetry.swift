import Foundation

struct TelemetryState {
  var lastHeartbeat: TimeInterval?
  var maximumHeartbeatGap: TimeInterval = 0
  var pendingWork = 0
  var latestSnapshot: [String: Any]?
  var correctnessFailures: [String] = []
  var events = 0

  static func read(_ url: URL) -> TelemetryState {
    guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8)
    else { return TelemetryState() }
    var state = TelemetryState()
    for line in text.split(separator: "\n") {
      guard let data = line.data(using: .utf8),
        let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      state.events += 1
      switch event["event"] as? String {
      case "heartbeat":
        if let uptime = event["uptime"] as? TimeInterval {
          if let previous = state.lastHeartbeat {
            state.maximumHeartbeatGap = max(state.maximumHeartbeatGap, uptime - previous)
          }
          state.lastHeartbeat = uptime
        }
      case "work-begin": state.pendingWork += 1
      case "work-end": state.pendingWork = max(0, state.pendingWork - 1)
      case "snapshot": state.latestSnapshot = event
      case "invariant":
        if let detail = event["detail"] as? String { state.correctnessFailures.append(detail) }
      default: break
      }
    }
    return state
  }
}
