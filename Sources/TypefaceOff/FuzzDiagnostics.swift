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
import TypefaceCore

#if TYPEFACEOFF_FUZZING
  @MainActor
  final class FuzzDiagnostics {
    static let shared = FuzzDiagnostics()

    private let writer: FuzzEventWriter?
    private var timer: Timer?
    private var generation: UInt64 = 0
    private var glyphGeometries:
      [String: (context: String, glyph: [Unicode.Scalar], baseline: Double)] = [:]

    private init() {
      guard let folder = ProcessInfo.processInfo.environment["TYPEFACEOFF_FUZZ_DIR"],
        !folder.isEmpty
      else {
        writer = nil
        return
      }
      let directory = URL(fileURLWithPath: folder)
      writer = FuzzEventWriter(url: directory.appendingPathComponent("telemetry.jsonl"))
      try! StandardStreamRedirect.append(
        stdout, to: directory.appendingPathComponent("stdout.log"), buffering: _IOLBF)
      try! StandardStreamRedirect.append(
        stderr, to: directory.appendingPathComponent("stderr.log"), buffering: _IONBF)
      emit(["event": "launch"])
      let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
        MainActor.assumeIsolated { FuzzDiagnostics.shared.heartbeat() }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }

    func snapshot(window: UUID, comparison: Comparison) {
      var event: [String: Any] = [
        "event": "snapshot",
        "window": window.uuidString,
        "a": comparison.a.postScriptName,
        "aSize": comparison.a.size,
        "aTracking": comparison.a.tracking,
        "aLeading": comparison.a.leading as Any? ?? "Auto",
        "aFeatures": comparison.a.features,
        "appearanceLocked": comparison.appearanceLocked,
        "mode": comparison.mode.rawValue,
        "sample": comparison.sample.rawValue,
        "selectedGlyph": comparison.selectedGlyph,
        "shape": comparison.shape,
        "spacing": comparison.spacing,
        "frequency": comparison.frequency,
        "textUTF16": comparison.text.utf16.count,
      ]
      if let b = comparison.b {
        event["b"] = b.postScriptName
        event["bSize"] = b.size
        event["bTracking"] = b.tracking
        event["bLeading"] = b.leading as Any? ?? "Auto"
        event["bFeatures"] = b.features
      }
      emit(event)
      checkInvariants(comparison)
    }

    func validateTypographyEdit(previous: Comparison, next: Comparison) {
      let changed = [
        previous.a.features != next.a.features,
        previous.b?.features != next.b?.features,
      ].filter { $0 }.count
      if changed > 1 { invariant("A typography edit changed both fonts") }
    }

    func beginWork(_ kind: String) -> UUID {
      let identifier = UUID()
      emit(["event": "work-begin", "kind": kind, "id": identifier.uuidString])
      return identifier
    }

    func endWork(_ identifier: UUID, kind: String, outcome: String = "completed") {
      emit([
        "event": "work-end", "kind": kind, "id": identifier.uuidString, "outcome": outcome,
      ])
    }

    func nextGeneration() -> UInt64 {
      generation += 1
      return generation
    }

    func measure<T>(
      _ kind: String, text: String, generation: UInt64, _ body: () -> T
    ) -> T {
      let id = UUID().uuidString
      let length = text.utf16.count
      let start = ProcessInfo.processInfo.systemUptime
      emit([
        "event": "work-begin", "kind": kind, "id": id,
        "textUTF16": length, "generation": generation,
      ])
      defer {
        emit([
          "event": "work-end", "kind": kind, "id": id,
          "textUTF16": length, "generation": generation,
          "durationSeconds": ProcessInfo.processInfo.systemUptime - start,
        ])
      }
      return body()
    }

    func glyphGeometry(
      view: String, context: String, glyph: [Unicode.Scalar], baseline: Double
    ) {
      if let previous = glyphGeometries[view], previous.context == context,
        previous.glyph != glyph, abs(previous.baseline - baseline) > 0.001
      {
        invariant("Glyph navigation moved the calibrated baseline")
      }
      glyphGeometries[view] = (context, glyph, baseline)
      emit([
        "event": "glyph-geometry", "view": view, "context": context,
        "glyph": String(String.UnicodeScalarView(glyph)),
        "baseline": baseline,
      ])
    }

    private func heartbeat() {
      emit(["event": "heartbeat"])
    }

    private func checkInvariants(_ comparison: Comparison) {
      let configs = [comparison.a, comparison.b].compactMap { $0 }
      for config in configs {
        if !config.size.isFinite || !(10...144).contains(config.size) {
          invariant("Point size escaped its native range")
        }
        if !config.tracking.isFinite || !(-0.12...0.15).contains(config.tracking) {
          invariant("Tracking escaped its native range")
        }
        if config.axes.values.contains(where: { !$0.isFinite }) {
          invariant("A variable-font axis became non-finite")
        }
        if let leading = config.leading,
          !leading.isFinite || !FontConfiguration.leadingRange.contains(leading)
        {
          invariant("Leading escaped its native range")
        }
      }
      if comparison.appearanceLocked, comparison.b != nil, comparison.link == nil {
        invariant("Linked appearance lost its calibration")
      }
      if comparison.b == nil, comparison.link != nil {
        invariant("A single-font comparison retained a two-font calibration")
      }
      if comparison.appearanceLocked, let b = comparison.b, let link = comparison.link {
        let linkedSize = min(144, max(10, comparison.a.size * link.sizeRatio))
        let reverseSize = min(144, max(10, b.size / link.sizeRatio))
        if abs(b.size - linkedSize) > 0.001 && abs(comparison.a.size - reverseSize) > 0.001 {
          invariant("Linked point sizes lost their calibrated ratio")
        }
        let linkedTracking = min(0.15, max(-0.12, comparison.a.tracking + link.trackingOffset))
        let reverseTracking = min(0.15, max(-0.12, b.tracking - link.trackingOffset))
        if abs(b.tracking - linkedTracking) > 0.000_001
          && abs(comparison.a.tracking - reverseTracking) > 0.000_001
        {
          invariant("Linked tracking lost its calibrated offset")
        }
        for (identifier, offset) in link.axisOffsets {
          guard let aValue = comparison.a.axes[identifier], let bValue = b.axes[identifier],
            let aAxis = comparison.a.face.axes.first(where: { $0.id == identifier }),
            let bAxis = b.face.axes.first(where: { $0.id == identifier })
          else { continue }
          let linked = min(bAxis.maximum, max(bAxis.minimum, aValue + offset))
          let reverse = min(aAxis.maximum, max(aAxis.minimum, bValue - offset))
          if abs(bValue - linked) > 0.000_001 && abs(aValue - reverse) > 0.000_001 {
            invariant("Linked variable-font axes lost their calibrated offsets")
          }
        }
        if let aLeading = comparison.a.leading, let bLeading = b.leading {
          let range = FontConfiguration.leadingRange
          let linked = min(range.upperBound, max(range.lowerBound, aLeading + link.leadingOffset))
          let reverse = min(range.upperBound, max(range.lowerBound, bLeading - link.leadingOffset))
          if abs(bLeading - linked) > 0.000_001 && abs(aLeading - reverse) > 0.000_001 {
            invariant("Linked leading lost its calibrated offset")
          }
        }
      }
    }

    private func invariant(_ detail: String) {
      emit(["event": "invariant", "detail": detail])
    }

    private func emit(_ values: [String: Any]) {
      guard let writer else { return }
      var event = values
      event["uptime"] = ProcessInfo.processInfo.systemUptime
      writer.write(event)
    }
  }

  private final class FuzzEventWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.typefaceoff.fuzz-events", qos: .utility)
    private let handle: FileHandle

    init?(url: URL) {
      do {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
          FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
      } catch {
        return nil
      }
    }

    func write(_ event: [String: Any]) {
      guard var encoded = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
      else { return }
      encoded.append(0x0a)
      let data = encoded
      queue.async { [handle, data] in
        do {
          try handle.write(contentsOf: data)
        } catch {
          // The external driver records missing telemetry as an automation failure.
        }
      }
    }
  }
#else
  @MainActor
  final class FuzzDiagnostics {
    static let shared = FuzzDiagnostics()

    private init() {}

    func snapshot(window: UUID, comparison: Comparison) {}

    func validateTypographyEdit(previous: Comparison, next: Comparison) {}

    func beginWork(_ kind: String) -> UUID { UUID() }

    func endWork(_ identifier: UUID, kind: String, outcome: String = "completed") {}

    func nextGeneration() -> UInt64 { 0 }

    func measure<T>(
      _ kind: String, text: String, generation: UInt64, _ body: () -> T
    ) -> T { body() }

    func glyphGeometry(
      view: String, context: String, glyph: [Unicode.Scalar], baseline: Double
    ) {}
  }
#endif
