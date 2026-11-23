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

import AppKit
import Foundation
import UIFuzzSupport

final class CampaignMonitor: @unchecked Sendable {
  private let lock = NSLock()
  private let url: URL
  private let identifier = UUID().uuidString.lowercased()
  private let mode: String
  private var timer: DispatchSourceTimer?
  private var observers: [NSObjectProtocol] = []
  private var error: (any Error)?
  private var previousDate = Date()
  private var previousUptime = ProcessInfo.processInfo.systemUptime
  private var desktop = DesktopSession.current().metadata
  private var execution: String?
  private var observingApp = false
  private var finished = false
  private var telemetry = TelemetryTail()
  private var lastGapHeartbeat: TimeInterval?

  init(artifacts: URL, mode: String) throws {
    url = artifacts.appending(path: "campaign-events.jsonl")
    self.mode = mode
    var startDetails = desktop
    startDetails["pid"] = String(ProcessInfo.processInfo.processIdentifier)
    startDetails["arguments"] = ProcessInfo.processInfo.arguments.joined(separator: " ")
    startDetails["operating-system"] = ProcessInfo.processInfo.operatingSystemVersionString
    try record("campaign-start", details: startDetails)
    for (name, event) in [
      (NSWorkspace.willSleepNotification, "suspension"),
      (NSWorkspace.didWakeNotification, "reconnection"),
      (NSWorkspace.sessionDidResignActiveNotification, "session-disconnected"),
      (NSWorkspace.sessionDidBecomeActiveNotification, "session-reconnected"),
    ] {
      observers.append(
        NSWorkspace.shared.notificationCenter.addObserver(
          forName: name, object: nil, queue: nil
        ) { [weak self] _ in
          self?.capture { try self?.record(event) }
        })
    }
    let timer = DispatchSource.makeTimerSource(
      queue: DispatchQueue(label: "ui-fuzz.campaign-events"))
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { [weak self] in self?.capture { try self?.poll() } }
    timer.resume()
    self.timer = timer
  }

  deinit {
    timer?.cancel()
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }

  func record(_ event: String, execution: String? = nil, details: [String: String] = [:]) throws {
    try lock.withLock {
      if let error { throw error }
      guard !finished else { return }
      if event == "execution-start" {
        self.execution = execution
        observingApp = true
        telemetry = TelemetryTail()
        lastGapHeartbeat = nil
      }
      try write(event, execution: execution ?? self.execution, details: details)
      if event == "execution-work-end" { observingApp = false }
      if event == "execution-end" { self.execution = nil }
    }
  }

  func checkFailure() throws {
    try lock.withLock { if let error { throw error } }
  }

  func observe(_ event: String, execution: String, details: [String: String]) {
    capture { try record(event, execution: execution, details: details) }
  }

  func finish(reason: String) {
    timer?.cancel()
    try! lock.withLock {
      if let error { throw error }
      finished = true
      try write("campaign-stop", execution: execution, details: ["reason": reason])
    }
  }

  private func capture(_ body: () throws -> Void) {
    do { try body() } catch { lock.withLock { self.error = error } }
  }

  private func poll() throws {
    try lock.withLock {
      guard !finished else { return }
      let now = Date()
      let uptime = ProcessInfo.processInfo.systemUptime
      let wallGap = now.timeIntervalSince(previousDate)
      let uptimeGap = uptime - previousUptime
      if wallGap > 3 || uptimeGap > 3 {
        try write(
          "observation-gap", execution: execution,
          details: [
            "wallSeconds": String(wallGap), "uptimeSeconds": String(uptimeGap),
            "possibleSuspension": String(wallGap - uptimeGap > 2),
          ])
      }
      previousDate = now
      previousUptime = uptime
      let current = DesktopSession.current().metadata
      if current != desktop {
        desktop = current
        try write("desktop-transition", execution: execution, details: current)
      }
      if observingApp, let execution {
        let file = url.deletingLastPathComponent().appending(
          path: "runs/\(execution)/telemetry.jsonl")
        let summary = telemetry.refresh { TelemetryFile.bytes(at: file, from: $0) }
        if let heartbeat = summary.lastHeartbeat, uptime - heartbeat >= 0.4,
          lastGapHeartbeat != heartbeat
        {
          lastGapHeartbeat = heartbeat
          try write(
            "heartbeat-gap-observed", execution: execution,
            details: [
              "heartbeat": String(heartbeat), "seconds": String(uptime - heartbeat),
              "pending": summary.pendingSummary,
            ])
        }
      }
      try write("campaign-heartbeat", execution: execution, details: desktop)
    }
  }

  private func write(_ event: String, execution: String?, details: [String: String]) throws {
    struct Event: Encodable {
      var event: String
      var campaign: String
      var mode: String
      var execution: String?
      var timestamp: Date
      var uptime: TimeInterval
      var source: String
      var vm: String?
      var details: [String: String]
    }
    let environment = ProcessInfo.processInfo.environment
    try ExecutionJournal.append(
      Event(
        event: event, campaign: identifier, mode: mode, execution: execution, timestamp: Date(),
        uptime: ProcessInfo.processInfo.systemUptime,
        source: environment["TYPEFACEOFF_FUZZ_VM"] == "1" ? "guest" : "host",
        vm: environment["TYPEFACEOFF_FUZZ_VM_NAME"], details: details), to: url)
  }
}
