import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct SchemaTests {
  static func encode<Value: Encodable>(_ value: Value, dates: Bool = false) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if dates { encoder.dateEncodingStrategy = .iso8601 }
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }

  static func keys<Value: Encodable>(_ value: Value, dates: Bool = false) throws -> Set<String> {
    let encoder = JSONEncoder()
    if dates { encoder.dateEncodingStrategy = .iso8601 }
    let object = try JSONSerialization.jsonObject(with: encoder.encode(value))
    return Set((object as! [String: Any]).keys)
  }

  static let action = FuzzAction(
    kind: .setValue, target: "T", value: "v", keyCode: 36, modifiers: 256, deltaX: 1.5,
    deltaY: -2, delayMilliseconds: 50, targetPath: [0, 1], targetRole: "AXTextField",
    commitValue: true)

  @Test func schemaIsFrozen() throws {
    #expect(FuzzTrace.schemaVersion == 1)
    #expect(
      try Self.encode(Self.action)
        == #"{"commitValue":true,"delayMilliseconds":50,"deltaX":1.5,"deltaY":-2,"keyCode":36,"kind":"setValue","modifiers":256,"target":"T","targetPath":[0,1],"targetRole":"AXTextField","value":"v"}"#
    )
    #expect(
      try Self.keys(Self.action) == [
        "commitValue", "delayMilliseconds", "deltaX", "deltaY", "keyCode", "kind", "modifiers",
        "target", "targetPath", "targetRole", "value",
      ])
    #expect(
      try Self.keys(FuzzAction(kind: .pause)) == ["delayMilliseconds", "kind"])

    let trace = FuzzTrace(seed: 7, actions: [Self.action], origin: "test")
    #expect(try Self.keys(trace) == ["actions", "origin", "seed", "version"])

    let finding = ExecutionFinding(
      kind: .automation, signature: "Control not found: x", detail: "d")
    #expect(
      try Self.encode(finding)
        == #"{"detail":"d","kind":"automation","signature":"Control not found: x"}"#)

    #expect(
      try Self.encode(CorpusState()) == #"{"countBuckets":[],"executions":0,"regions":[]}"#)

    let report = ExecutionReport(
      trace: trace, startedAt: Date(timeIntervalSince1970: 0), durationMilliseconds: 1,
      workloadDurationMilliseconds: 2, actionMilliseconds: [3], coverage: ["r"],
      countBuckets: ["b"], findings: [finding], exitStatus: 0, terminatedByWatchdog: true,
      metadata: ["k": "v"])
    #expect(
      try Self.keys(report, dates: true) == [
        "actionMilliseconds", "countBuckets", "coverage", "durationMilliseconds", "exitStatus",
        "findings", "metadata", "startedAt", "terminatedByWatchdog", "trace",
        "workloadDurationMilliseconds",
      ])
    let sparse = ExecutionReport(
      trace: trace, startedAt: Date(timeIntervalSince1970: 0), durationMilliseconds: 1,
      actionMilliseconds: [])
    #expect(
      try Self.keys(sparse, dates: true) == [
        "actionMilliseconds", "countBuckets", "coverage", "durationMilliseconds", "findings",
        "metadata", "startedAt", "terminatedByWatchdog", "trace",
      ])
  }

  @Test func legacyTracesStillDecode() throws {
    let legacy = Data(
      #"{"version":1,"seed":7,"origin":"generated","actions":[{"kind":"press","target":"Swap fonts","delayMilliseconds":30},{"kind":"scroll","targetPath":[0,0,20,7],"targetRole":"AXScrollArea","deltaX":1,"deltaY":2,"delayMilliseconds":50}]}"#
        .utf8)
    let trace = try JSONDecoder().decode(FuzzTrace.self, from: legacy)
    #expect(trace.version == 1)
    #expect(
      trace.actions[0] == FuzzAction(kind: .press, target: "Swap fonts", delayMilliseconds: 30))
    #expect(trace.actions[1].targetPath == [0, 0, 20, 7])
    #expect(trace.actions[1].target == nil)
    #expect(trace.actions[1].commitValue == nil)
  }

  @Test func theSheetTagIsOptionalAndRoundTrips() throws {
    let tagged = FuzzAction(kind: .press, target: "Optical Size", sheet: .match)
    #expect(
      try Self.encode(tagged)
        == #"{"delayMilliseconds":30,"kind":"press","sheet":"match","target":"Optical Size"}"#)
    let editor = Data(
      #"{"version":1,"seed":7,"origin":"exploration","actions":[{"kind":"press","target":"Apply","sheet":"editor","delayMilliseconds":30},{"kind":"press","target":"Apply","delayMilliseconds":30}]}"#
        .utf8)
    let trace = try JSONDecoder().decode(FuzzTrace.self, from: editor)
    #expect(trace.actions[0].sheet == .editor)
    #expect(trace.actions[1].sheet == nil)
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "schema-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "tagged.json")
    let saved = FuzzTrace(seed: 1, actions: [tagged, Self.action])
    try TraceIO.save(saved, to: url)
    #expect(try TraceIO.load(url) == saved)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        FuzzTrace.self,
        from: Data(
          #"{"version":1,"seed":7,"origin":"x","actions":[{"kind":"press","sheet":"popover","delayMilliseconds":30}]}"#
            .utf8))
    }
  }

  @Test func loadRejectsOtherSchemaVersions() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "schema-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    var trace = FuzzTrace(seed: 1, actions: [Self.action])
    let good = directory.appending(path: "good.json")
    try TraceIO.save(trace, to: good)
    #expect(try TraceIO.load(good) == trace)
    trace.version = 99
    let bad = directory.appending(path: "bad.json")
    try TraceIO.save(trace, to: bad)
    #expect(throws: TraceIO.TraceError.unsupportedVersion(99)) { try TraceIO.load(bad) }
  }

  @Test func onlyTargetedKindsNeedATarget() {
    let needing: Set<FuzzAction.Kind> = [
      .press, .setValue, .increment, .decrement, .showMenu, .scroll, .selectFont, .click, .drag,
    ]
    #expect(FuzzAction.Kind.allCases.count == 14)
    for kind in FuzzAction.Kind.allCases { #expect(kind.needsTarget == needing.contains(kind)) }
    #expect(!FuzzAction.Kind.shortcut.needsTarget)
    #expect(!FuzzAction.Kind.key.needsTarget)
    #expect(!FuzzAction.Kind.pause.needsTarget)
  }

  static func finding(
    _ signature: String, kind: ExecutionFinding.Kind = .automation
  ) -> ExecutionFinding {
    ExecutionFinding(kind: kind, signature: signature, detail: "")
  }

  @Test func aControlFindingReproducesForTheSameControlInEitherFamily() {
    let missing = Self.finding("Control not found: Font B Size")
    let ambiguous = Self.finding("Ambiguous control: Font B Size")
    #expect(missing.reproduces(missing))
    #expect(ambiguous.reproduces(missing))
    #expect(missing.reproduces(ambiguous))
    #expect(ambiguous.reproduces(ambiguous))
    let path = Self.finding("Control not found: [0, 0, 20, 7]")
    #expect(path.reproduces(path))
    #expect(!path.reproduces(missing))
    #expect(!Self.finding("Control not found: Font A Size").reproduces(missing))
    #expect(!Self.finding("Ambiguous control: Font A Size").reproduces(missing))
  }

  @Test func otherFindingsNeedEqualKindAndSignature() {
    let missing = Self.finding("Control not found: x")
    #expect(!Self.finding("Control not found: x", kind: .hang).reproduces(missing))
    #expect(!Self.finding("Control not found: x", kind: .crash).reproduces(missing))
    #expect(!Self.finding("Accessibility action AXPress failed: -25200").reproduces(missing))
    let press = Self.finding("Accessibility action AXPress failed: -25200")
    #expect(press.reproduces(press))
    #expect(!Self.finding("Accessibility action AXPress failed: -25201").reproduces(press))
    let unprefixed = Self.finding("x")
    #expect(!unprefixed.reproduces(missing))
    #expect(!missing.reproduces(unprefixed))
    #expect(unprefixed.reproduces(unprefixed))
    #expect(!Self.finding("Control not found:").reproduces(unprefixed))
  }

  @Test func aPersistentFindingReproducesOnlyItself() {
    let persistent = Self.finding("Persistent stale control: AXButton Size")
    let missing = Self.finding("Control not found: AXButton Size")
    #expect(persistent.reproduces(persistent))
    #expect(!persistent.reproduces(missing))
    #expect(!missing.reproduces(persistent))
    #expect(!Self.finding("Persistent stale control: AXButton Size ").reproduces(persistent))
  }

  @Test func sideFileFindingsNeverStandForThePrimaryFinding() {
    let primary = Self.finding("Control not found: Font B Size")
    let diagnostics = Self.finding("diagnostics-write")
    let driverLog = Self.finding("driver-log-write")
    #expect(diagnostics.isSideFileFailure && driverLog.isSideFileFailure)
    #expect(!primary.isSideFileFailure)
    let findings = [primary, diagnostics, driverLog]
    let target = findings[0]
    #expect(findings.contains { $0.reproduces(target) })
    #expect(!findings.dropFirst().contains { $0.reproduces(target) })
    #expect(!diagnostics.reproduces(diagnostics))
    #expect(!driverLog.reproduces(driverLog))
    #expect(!primary.reproduces(diagnostics))
  }
}
