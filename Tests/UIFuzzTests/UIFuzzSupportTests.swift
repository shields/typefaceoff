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
    #expect(seeds.count == 16)
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
    #expect(fonts.suffix(2).map { $0.actions[0].target } == ["Font A family", "Font B family"])
    #expect(fonts.suffix(2).allSatisfy { ["A", "B"].contains($0.actions[0].value ?? "") })
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

  @Test func installedFontsDoNotCrowdOutUIActionsOrStartup() {
    let families = (0..<2000).map { "Family \($0)" }
    let mutator = TraceMutator(maximumTextUnits: 32, installedFontFamilies: families)
    #expect(mutator.initialCorpus(seed: 42).count == 18)
    #expect(mutator.initialCorpus(seed: 42) == mutator.initialCorpus(seed: 42))
    let actions = (0..<2000).flatMap {
      mutator.mutate(FuzzTrace(seed: 0), seed: UInt64($0)).actions
    }
    for target in [
      "Swap fonts", "Match…", "Sample selector", "Toggle comparison inspector", "Search characters",
      "Font B Optimize tracking", "Font B Optimize size",
    ] {
      #expect(actions.contains { $0.kind == .press && $0.target == target })
    }
    #expect(
      !actions.contains { $0.kind == .press && ["Tracking", "Weight"].contains($0.target ?? "") })
    for side in ["A", "B"] {
      #expect(actions.contains { $0.kind == .selectFont && $0.target == "Font \(side) family" })
      for kind: FuzzAction.Kind in [.click, .scroll] {
        #expect(actions.contains { $0.kind == kind && $0.target == "Font \(side) specimen" })
      }
    }
  }

  @Test func campaignExploresImmediatelyAndOnResumeWithLegacyFontSeeds() {
    let mutator = TraceMutator(maximumTextUnits: 32, installedFontFamilies: ["A", "B"])
    let legacy = (0..<2000).map {
      FuzzTrace(
        seed: UInt64($0),
        actions: [FuzzAction(kind: .selectFont, target: "Font A family", value: "Family \($0)")],
        origin: "seed")
    }
    for execution in 0..<100 {
      let trace = mutator.campaignTrace(
        execution: execution, corpus: legacy, seed: UInt64(execution))
      #expect(
        trace
          == mutator.campaignTrace(execution: execution, corpus: legacy, seed: UInt64(execution)))
      if execution.isMultiple(of: 2) {
        #expect(trace.origin == "exploration")
        #expect(trace.actions.isEmpty)
      } else {
        #expect(!trace.actions.isEmpty)
      }
    }
    #expect(mutator.campaignTrace(execution: 998, corpus: legacy, seed: 0).origin == "exploration")
    #expect(mutator.campaignTrace(execution: 999, corpus: [], seed: 0).origin == "mutation")
  }

  @Test func explorationBalancesKindsAndDistinctControls() {
    var explorer = ActionExplorer(mutator: TraceMutator())
    var random = SplitMix64(seed: 42)
    let buttons = (0..<1000).map {
      FuzzAction(kind: .press, target: "Duplicate label", targetPath: [$0], targetRole: "AXButton")
    }
    let candidates = buttons + [FuzzAction(kind: .scroll, target: "Inspector")]
    var actions: [FuzzAction] = []
    for _ in 0..<100 { actions.append(explorer.next(from: candidates, using: &random)) }
    let pressed = actions.filter { $0.kind == .press }
    #expect(pressed.count == 50)
    #expect(Set(pressed.compactMap(\.targetPath)).count == 50)
    #expect(actions.filter { $0.kind == .scroll }.count == 50)
    #expect(explorer.next(from: [], using: &random).keyCode == 53)
  }

  @Test func explorationGeneratesReplayableBoundedValuesAndKeyboardInput() {
    let mutator = TraceMutator(maximumTextUnits: 32, installedFontFamilies: ["Font"])
    var first = ActionExplorer(mutator: mutator)
    var second = ActionExplorer(mutator: mutator)
    var left = SplitMix64(seed: 7)
    var right = SplitMix64(seed: 7)
    let edits = [
      "Search installed fonts", "Find Character", "Search Unicode characters", "Search Languages",
      "Character", "Custom specimen text",
      "Size",
    ].map {
      FuzzAction(
        kind: .setValue, target: $0, targetPath: [1, 2], targetRole: "AXTextField",
        commitValue: false)
    }
    let candidates =
      edits + [FuzzAction(kind: .drag, target: "Canvas")]
      + ActionExplorer.keyboardActions(includeShortcuts: true)
    #expect(ActionExplorer.keyboardActions(includeShortcuts: false).allSatisfy { $0.kind == .key })
    #expect(candidates.contains { $0.kind == .shortcut })
    let menuKeys = ActionExplorer.keyboardActions(includeShortcuts: false, inMenu: true)
    #expect(menuKeys.compactMap(\.keyCode) == [53, 123, 124, 125, 126])
    #expect(
      ActionExplorer.keyboardActions(includeShortcuts: false).compactMap(\.keyCode)
        == [36, 48, 53, 123, 124, 125, 126])
    for _ in 0..<200 {
      let action = first.next(from: candidates, using: &left)
      #expect(action == second.next(from: candidates, using: &right))
      if action.kind == .setValue {
        #expect(action.value != nil)
        #expect(action.targetPath == [1, 2])
        #expect(action.targetRole == "AXTextField")
        #expect(action.commitValue == false)
        if action.target == "Custom specimen text" { #expect(action.value!.utf16.count <= 32) }
      }
      if action.kind == .drag {
        #expect((-60...60).contains(action.deltaX!))
        #expect((-120...120).contains(action.deltaY!))
      }
    }
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
      deltaX: 1, deltaY: -2, delayMilliseconds: 9,
      targetPath: [1, 0, 3], targetRole: "AXScrollArea", commitValue: false)
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

  @Test func availabilityBackoffCapsRetriesAndResetsAfterRecovery() {
    var backoff = CampaignBackoff()
    #expect(backoff.delaySeconds == 0)
    #expect((0..<6).map { _ in backoff.failed() } == [5, 10, 20, 40, 60, 60])
    for _ in 0..<1000 { backoff.failed() }
    #expect(backoff.delaySeconds == 60)
    backoff.recovered()
    #expect(backoff.delaySeconds == 0)
    #expect(backoff.failed() == 5)
  }

  @Test func unavailableDesktopCannotHideProductFailuresOrBecomeABenchmark() {
    var report = ExecutionReport(
      trace: FuzzTrace(seed: 1, actions: [FuzzAction(kind: .press, target: "Text")]),
      startedAt: Date(), durationMilliseconds: 100, workloadDurationMilliseconds: 50,
      actionMilliseconds: [10])
    #expect(!report.needsAvailabilityRecovery)
    #expect(report.isBenchmarkSample)
    report.actionMilliseconds = []
    #expect(!report.isBenchmarkSample)
    report.findings = [
      ExecutionFinding(kind: .unavailable, signature: "workbench", detail: "unavailable")
    ]
    #expect(report.needsAvailabilityRecovery)
    #expect(!report.isBenchmarkSample)
    report.findings.append(
      ExecutionFinding(kind: .automation, signature: "coverage-export", detail: "missing"))
    #expect(report.needsAvailabilityRecovery)
    for kind: ExecutionFinding.Kind in [.crash, .hang, .correctness] {
      var failed = report
      failed.findings.append(ExecutionFinding(kind: kind, signature: "failure", detail: "failure"))
      #expect(!failed.needsAvailabilityRecovery)
      #expect(!failed.isBenchmarkSample)
    }
    report.findings = []
    report.actionMilliseconds = [10]
    report.workloadDurationMilliseconds = nil
    #expect(!report.isBenchmarkSample)
    report.workloadDurationMilliseconds = 50
    report.findings = [
      ExecutionFinding(kind: .automation, signature: "missing-control", detail: "missing")
    ]
    #expect(!report.needsAvailabilityRecovery)
    #expect(!report.isBenchmarkSample)
  }
}
