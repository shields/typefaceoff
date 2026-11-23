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
import UIFuzzSupport

enum StartupSelfTest {
  static func run(configuration: RunnerConfiguration) {
    testProcessLiveness()

    let artifacts = configuration.artifacts.appending(path: ".startup-self-test")
    if FileManager.default.fileExists(atPath: artifacts.path) {
      try! FileManager.default.removeItem(at: artifacts)
    }
    var testConfiguration = configuration
    testConfiguration.artifacts = artifacts
    testConfiguration.collectCoverage = false
    defer { try! FileManager.default.removeItem(at: artifacts) }

    let command = UInt64(1 << 20)
    let glyphMode = FuzzAction(
      kind: .shortcut, keyCode: 19, modifiers: command, delayMilliseconds: 400)
    let runner = SequenceRunner(configuration: testConfiguration)

    let glyph = run(
      FuzzTrace(seed: 0, actions: [glyphMode], origin: "startup-self-test"), using: runner)
    precondition(glyph["mode"] as? String == "glyph")

    let canvas = run(
      FuzzTrace(
        seed: 1,
        actions: [glyphMode, FuzzAction(kind: .click, target: "Glyph canvas")],
        origin: "startup-self-test"),
      using: runner)
    precondition(canvas["mode"] as? String == "text")

    let specimen = "Hamburg 🦄 e\u{301}"
    let edited = run(
      FuzzTrace(
        seed: 2,
        actions: [FuzzAction(kind: .setSpecimen, value: specimen, delayMilliseconds: 400)],
        origin: "startup-self-test"),
      using: runner)
    precondition(edited["textUTF16"] as? Int == specimen.utf16.count)
  }

  private static func run(_ trace: FuzzTrace, using runner: SequenceRunner) -> [String: Any] {
    let report = try! runner.execute(trace)
    precondition(report.findings.isEmpty)
    let snapshot = report.metadata["final-snapshot"]!
    return try! JSONSerialization.jsonObject(with: Data(snapshot.utf8)) as! [String: Any]
  }

  private static func testProcessLiveness() {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["60"]
    try! child.run()
    precondition(ProcessLiveness.isAlive(child.processIdentifier))
    child.terminate()
    precondition(ProcessLiveness.waitForExit(child.processIdentifier, timeout: 0.1))
  }
}
