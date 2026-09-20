import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct UIFuzzSupportTests {
  @Test func randomGeneratorAndMutationAreDeterministicAndBounded() {
    var first = SplitMix64(seed: 42)
    var second = SplitMix64(seed: 42)
    #expect((0..<20).map { _ in first.next() } == (0..<20).map { _ in second.next() })

    let mutator = TraceMutator(maximumActions: 4, maximumTextUnits: 32)
    let seeds = mutator.initialCorpus(seed: 1)
    #expect(seeds.count == 15)
    #expect(seeds.allSatisfy { !$0.actions.isEmpty && $0.origin == "seed" })
    let input = FuzzTrace(seed: 7, actions: seeds.flatMap(\.actions), origin: "test")
    for seed in 0..<200 {
      let left = mutator.mutate(input, seed: UInt64(seed))
      let right = mutator.mutate(input, seed: UInt64(seed))
      #expect(left == right)
      #expect((1...4).contains(left.actions.count))
      #expect(left.origin == "mutation")
      for action in left.actions
      where action.kind == .setValue && action.target == "Custom specimen text" {
        #expect((action.value ?? "").utf16.count <= 32)
      }
    }
    let fontMutator = TraceMutator(maximumTextUnits: 32, installedFontFamilies: ["A", "B"])
    let fonts = fontMutator.initialCorpus(seed: 2)
    #expect(fonts.suffix(2).map { $0.actions[0].value } == ["A", "B"])
    let selected = (0..<100).flatMap {
      fontMutator.mutate(FuzzTrace(seed: 1), seed: UInt64($0)).actions
    }
    #expect(selected.contains { $0.kind == .selectFont && ["A", "B"].contains($0.value ?? "") })

    let tightlyBounded = TraceMutator(maximumActions: 1, maximumTextUnits: 4)
    #expect(tightlyBounded.initialCorpus(seed: 3).allSatisfy { $0.actions.count == 1 })
    let oversized = FuzzTrace(
      seed: 4,
      actions: [
        FuzzAction(kind: .setValue, target: "Custom specimen text", value: "Hamburg 🦄"),
        FuzzAction(kind: .pause),
      ])
    let constrained = tightlyBounded.constrained(oversized)
    #expect(constrained.actions.count == 1)
    #expect(constrained.actions[0].value?.utf16.count == 4)
  }

  @Test func corpusReportsOnlyNewFeedback() {
    var corpus = CorpusState()
    let first = corpus.consider(regions: ["a", "b"], countBuckets: ["a=1"])
    #expect(first.regions == ["a", "b"])
    #expect(first.countBuckets == ["a=1"])
    #expect(first.isInteresting)
    let repeated = corpus.consider(regions: ["a"], countBuckets: ["a=1"])
    #expect(!repeated.isInteresting)
    #expect(corpus.executions == 2)
    #expect(CoverageBuckets.bucket(0) == 0)
    #expect(CoverageBuckets.bucket(1) == 1)
    #expect(CoverageBuckets.bucket(7) == 4)
  }

  @Test func reducerRemovesChunksAndKeepsRequiredAction() throws {
    let required = FuzzAction(kind: .press, target: "required")
    let trace = FuzzTrace(
      seed: 1,
      actions: [
        FuzzAction(kind: .pause), FuzzAction(kind: .press, target: "extra"), required,
        FuzzAction(kind: .pause),
      ])
    let reduced = TraceReducer.reduce(trace) { $0.contains(required) }
    #expect(reduced.actions == [required])
    #expect(reduced.origin == "minimized")
    #expect(Statistics.median([]) == nil)
    #expect(Statistics.median([3]) == 3)
    #expect(Statistics.median([4, 1, 3, 2]) == 2.5)
  }

  @Test func tracesAndReportsRoundTripAndRejectOtherVersions() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let traceURL = folder.appending(path: "trace.json")
    let reportURL = folder.appending(path: "report.json")
    let action = FuzzAction(
      kind: .scroll, target: "canvas", value: "value", keyCode: 4, modifiers: 8,
      deltaX: 1, deltaY: -2, delayMilliseconds: 9)
    let trace = FuzzTrace(seed: 123, actions: [action])
    try TraceIO.save(trace, to: traceURL)
    #expect(try TraceIO.load(traceURL) == trace)
    let finding = ExecutionFinding(kind: .correctness, signature: "invariant", detail: "detail")
    let report = ExecutionReport(
      trace: trace, startedAt: Date(timeIntervalSince1970: 1), durationMilliseconds: 12,
      workloadDurationMilliseconds: 10,
      actionMilliseconds: [1], coverage: ["region"], countBuckets: ["region=1"],
      findings: [finding], exitStatus: 0, terminatedByWatchdog: false,
      metadata: ["key": "value"])
    #expect(report.pacingMilliseconds == 9)
    #expect(report.measuredMilliseconds == 1)
    let reportWithoutWorkloadTiming = ExecutionReport(
      trace: trace, startedAt: Date(timeIntervalSince1970: 1), durationMilliseconds: 12,
      actionMilliseconds: [1])
    #expect(reportWithoutWorkloadTiming.measuredMilliseconds == 3)
    try TraceIO.save(report, to: reportURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(ExecutionReport.self, from: Data(contentsOf: reportURL)) == report)

    var invalid = trace
    invalid.version = 99
    try JSONEncoder().encode(invalid).write(to: traceURL)
    #expect(throws: TraceIO.TraceError.unsupportedVersion(99)) { try TraceIO.load(traceURL) }
  }
}
