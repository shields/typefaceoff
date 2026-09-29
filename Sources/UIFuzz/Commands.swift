import ArgumentParser
import CoreText
import Foundation
import UIFuzzSupport

@main
struct UIFuzz: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ui-fuzz",
    abstract: "Coverage-directed UI fuzzing for Typeface/Off.",
    subcommands: [Run.self, Replay.self, Minimize.self, Benchmark.self])
}

struct CommonOptions: ParsableArguments {
  @Option(help: "Path to the diagnostic TypefaceOff.app.")
  var app: String

  @Option(help: "Directory for the corpus, findings, telemetry, and reports.")
  var artifacts = ".build/ui-fuzz"

  @Option(help: "Seconds without a main-thread heartbeat before declaring a hang.")
  var watchdog = 10.0

  @Option(help: "Seconds allowed for the latest asynchronous UI work to finish.")
  var completionTimeout = 30.0

  mutating func validate() throws {
    guard watchdog > 0, completionTimeout > 0 else {
      throw ValidationError("Watchdog and completion timeouts must be positive.")
    }
  }

  var runnerConfiguration: RunnerConfiguration {
    RunnerConfiguration(
      app: URL(fileURLWithPath: app), artifacts: URL(fileURLWithPath: artifacts),
      watchdogSeconds: watchdog, completionSeconds: completionTimeout)
  }
}

struct Run: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Run a resumable campaign until interrupted.")

  @OptionGroup var common: CommonOptions

  @Option(help: "Random seed. Defaults to the current time.")
  var seed: UInt64?

  @Option(help: "Optional bound such as 30s, 10m, or 2h. Omit to run until interrupted.")
  var duration: String?

  @Option(help: "Maximum actions in one sequence.")
  var maxActions = 512

  @Option(help: "Maximum UTF-16 code units in generated specimen text.")
  var maxTextUnits = 100_000

  mutating func run() throws {
    guard maxActions > 0 else { throw ValidationError("--max-actions must be positive.") }
    guard maxTextUnits >= 0 else { throw ValidationError("--max-text-units cannot be negative.") }
    AXDriver.waitForPermissions()
    let stop = StopController()
    stop.install()
    let durationSeconds = try duration.map(parseDuration)
    let deadline = durationSeconds.map { ProcessInfo.processInfo.systemUptime + $0 }
    let campaignSeed = seed ?? UInt64(Date().timeIntervalSince1970.bitPattern)
    var random = SplitMix64(seed: campaignSeed)
    let installedFonts = (CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []).sorted()
    let mutator = TraceMutator(
      maximumActions: maxActions, maximumTextUnits: maxTextUnits,
      installedFontFamilies: installedFonts)
    let artifactURL = URL(fileURLWithPath: common.artifacts)
    let corpusURL = artifactURL.appending(path: "corpus")
    try FileManager.default.createDirectory(at: corpusURL, withIntermediateDirectories: true)
    var corpus = try loadCorpus(corpusURL).map(mutator.constrained)
    if corpus.isEmpty {
      corpus = mutator.initialCorpus(seed: campaignSeed)
      for (index, trace) in corpus.enumerated() {
        try TraceIO.save(trace, to: corpusURL.appending(path: "seed-\(index).json"))
      }
    }
    var state = try loadState(artifactURL.appending(path: "campaign.json"))
    let runner = SequenceRunner(configuration: common.runnerConfiguration, mutator: mutator)
    var slowest = try loadSlowCandidates(artifactURL)
    var backoff = CampaignBackoff()
    var desktopUnavailableReason: String?
    var pendingTrace: FuzzTrace?
    outputLine(
      "seed \(campaignSeed); \(corpus.count) corpus entries; \(installedFonts.count) installed font families; running until interrupted"
    )

    while !stop.isStopped && deadline.map({ ProcessInfo.processInfo.systemUptime < $0 }) != false {
      let reason = DesktopSession.current().unavailableReason
      if reason != desktopUnavailableReason {
        outputLine(
          reason.map { "waiting for desktop: \($0)" } ?? "desktop available; resuming campaign")
        desktopUnavailableReason = reason
      }
      if reason != nil {
        stop.wait(seconds: 0.5, deadline: deadline)
        continue
      }
      let trace =
        pendingTrace
        ?? mutator.campaignTrace(
          execution: state.executions, corpus: corpus, seed: random.next())
      pendingTrace = trace
      let report = runner.execute(
        trace, explorationActions: trace.origin == "exploration" ? min(maxActions, 32) : 0)
      if report.needsAvailabilityRecovery {
        try preserveAvailability(report, artifacts: artifactURL)
        let unavailable = report.findings.first(where: { $0.kind == .unavailable })!
        if unavailable.signature != DesktopSession.unavailableSignature
          && DesktopSession.current().unavailableReason == nil
        {
          outputLine(
            "waiting for workbench: \(unavailable.detail) Retrying in \(Int(backoff.failed())) seconds."
          )
          stop.wait(seconds: backoff.delaySeconds, deadline: deadline)
        }
        continue
      }
      if backoff.delaySeconds > 0 {
        outputLine("workbench available; resuming campaign")
      }
      backoff.recovered()
      pendingTrace = nil
      let delta = state.consider(regions: report.coverage, countBuckets: report.countBuckets)
      let identifier = String(format: "%08d-%016llx", state.executions, trace.seed)
      if delta.isInteresting {
        corpus.append(report.trace)
        try TraceIO.save(report.trace, to: corpusURL.appending(path: "\(identifier).json"))
      }
      try preserveFindings(report, identifier: identifier, artifacts: artifactURL)
      slowest = try preserveSlowCandidate(
        report, identifier: identifier, artifacts: artifactURL, current: slowest)
      try saveState(state, to: artifactURL.appending(path: "campaign.json"))
      let findingKinds = report.findings.map(\.kind.rawValue).joined(separator: ",")
      let inputs = Dictionary(grouping: report.trace.actions, by: \.kind.rawValue)
        .sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.count)" }.joined(separator: ",")
      outputLine(
        "#\(state.executions) mode=\(trace.origin) actions=\(report.actionMilliseconds.count)/\(report.trace.actions.count) measured-ms=\(Int(report.measuredMilliseconds)) total-ms=\(Int(report.durationMilliseconds)) "
          + "new=\(delta.regions.count)/\(delta.countBuckets.count)"
          + " inputs=\(inputs)"
          + (findingKinds.isEmpty ? "" : " findings=\(findingKinds)"))
    }
    outputLine("stopped after \(state.executions) executions; corpus has \(corpus.count) entries")
  }
}

struct Replay: ParsableCommand {
  @OptionGroup var common: CommonOptions
  @Option(name: .customLong("case"), help: "Trace or execution report to replay.")
  var casePath: String

  mutating func run() throws {
    AXDriver.waitForPermissions()
    let trace = try loadTraceOrReport(URL(fileURLWithPath: casePath)).trace
    let report = SequenceRunner(configuration: common.runnerConfiguration).execute(trace)
    let output = URL(fileURLWithPath: common.artifacts).appending(path: "replay.json")
    try TraceIO.save(report, to: output)
    printReport(report, output: output)
  }
}

struct Minimize: ParsableCommand {
  @OptionGroup var common: CommonOptions
  @Option(name: .customLong("case"), help: "Finding report to minimize.")
  var casePath: String

  mutating func run() throws {
    AXDriver.waitForPermissions()
    let original = try loadTraceOrReport(URL(fileURLWithPath: casePath))
    let runner = SequenceRunner(configuration: common.runnerConfiguration)
    guard let target = original.report?.findings.first else {
      throw ValidationError("Minimization requires an execution report containing a finding.")
    }
    let baseline = original.report?.measuredMilliseconds
    let minimized = TraceReducer.reduce(original.trace) { actions in
      var candidate = original.trace
      candidate.actions = actions
      if target.kind == .slow, let baseline {
        let reports = (0..<3).map { _ in runner.execute(candidate) }
        guard reports.allSatisfy(\.isBenchmarkSample) else { return false }
        let values = reports.map(\.measuredMilliseconds)
        return (Statistics.median(values) ?? 0) >= baseline * 0.9
      }
      let report = runner.execute(candidate)
      return report.findings.contains {
        $0.kind == target.kind && $0.signature == target.signature
      }
    }
    let output = URL(fileURLWithPath: common.artifacts).appending(path: "minimized.json")
    try TraceIO.save(minimized, to: output)
    outputLine(
      "reduced \(original.trace.actions.count) actions to \(minimized.actions.count): \(output.path)"
    )
  }
}

struct Benchmark: ParsableCommand {
  @OptionGroup var common: CommonOptions
  @Option(help: "Directory containing trace JSON files.")
  var corpus: String
  @Option(help: "Repetitions per trace.")
  var repetitions = 5

  mutating func run() throws {
    guard repetitions > 0 else { throw ValidationError("--repetitions must be positive.") }
    AXDriver.waitForPermissions()
    var configuration = common.runnerConfiguration
    configuration.collectCoverage = false
    let runner = SequenceRunner(configuration: configuration)
    let traces = try loadCorpus(URL(fileURLWithPath: corpus))
    var results: [[String: Any]] = []
    var failedSamples = 0
    for trace in traces {
      let reports = (0..<repetitions).map { _ in runner.execute(trace) }
      let successful = reports.filter(\.isBenchmarkSample)
      let failed = reports.filter { !$0.isBenchmarkSample }
      failedSamples += failed.count
      let values = successful.map(\.measuredMilliseconds)
      let actionMedians = trace.actions.indices.map { index in
        Statistics.median(
          successful.compactMap {
            $0.actionMilliseconds.indices.contains(index) ? $0.actionMilliseconds[index] : nil
          }
        ).map { $0 as Any } ?? NSNull()
      }
      results.append([
        "seed": trace.seed, "actions": trace.actions.count,
        "medianMeasuredMilliseconds": Statistics.median(values).map { $0 as Any } ?? NSNull(),
        "minimumMilliseconds": values.min().map { $0 as Any } ?? NSNull(),
        "maximumMilliseconds": values.max().map { $0 as Any } ?? NSNull(),
        "samplesMilliseconds": values, "actionMedianMilliseconds": actionMedians,
        "successfulRepetitions": successful.count, "failedRepetitions": failed.count,
        "failures": failed.map { report in
          [
            "run": report.metadata["run"] ?? "",
            "findings": report.findings.map { finding in
              [
                "kind": finding.kind.rawValue, "signature": finding.signature,
                "detail": finding.detail,
              ]
            },
          ] as [String: Any]
        },
        "configuredPacingMilliseconds": trace.actions.map(\.delayMilliseconds).reduce(0, +),
        "processModel": "fresh",
      ])
    }
    results.sort {
      ($0["medianMeasuredMilliseconds"] as? Double ?? 0)
        > ($1["medianMeasuredMilliseconds"] as? Double ?? 0)
    }
    let output = URL(fileURLWithPath: common.artifacts).appending(path: "benchmark.json")
    try FileManager.default.createDirectory(
      at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
      .write(to: output, options: .atomic)
    outputLine("benchmarked \(traces.count) traces: \(output.path)")
    if failedSamples > 0 {
      throw ValidationError(
        "\(failedSamples) benchmark executions failed; their timings were excluded. See \(output.path)."
      )
    }
  }
}

private final class StopController: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false
  private var sources: [DispatchSourceSignal] = []

  var isStopped: Bool { lock.withLock { stopped } }

  func wait(seconds: TimeInterval, deadline: TimeInterval?) {
    let until = min(ProcessInfo.processInfo.systemUptime + seconds, deadline ?? .infinity)
    while !isStopped && ProcessInfo.processInfo.systemUptime < until {
      Thread.sleep(forTimeInterval: min(0.1, max(0, until - ProcessInfo.processInfo.systemUptime)))
    }
  }

  func install() {
    for signalNumber in [SIGINT, SIGTERM] {
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber)
      source.setEventHandler { [weak self] in self?.lock.withLock { self?.stopped = true } }
      source.resume()
      sources.append(source)
    }
  }
}

private func parseDuration(_ value: String) throws -> TimeInterval {
  let unit = value.last
  let multiplier: Double
  let number: Substring
  switch unit {
  case "s":
    multiplier = 1
    number = value.dropLast()
  case "m":
    multiplier = 60
    number = value.dropLast()
  case "h":
    multiplier = 3600
    number = value.dropLast()
  default:
    multiplier = 1
    number = Substring(value)
  }
  guard let result = Double(number), result > 0 else {
    throw ValidationError("Invalid duration: \(value)")
  }
  return result * multiplier
}

private func loadCorpus(_ directory: URL) throws -> [FuzzTrace] {
  try ArtifactLoader.corpus(in: directory)
}

private func loadState(_ url: URL) throws -> CorpusState {
  try ArtifactLoader.corpusState(at: url)
}

private func saveState(_ state: CorpusState, to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(state).write(to: url, options: .atomic)
}

private func preserveFindings(_ report: ExecutionReport, identifier: String, artifacts: URL) throws
{
  for kind in Set(report.findings.map(\.kind)) where kind != .slow {
    let output = artifacts.appending(path: "findings/\(kind.rawValue)/\(identifier).json")
    try TraceIO.save(report, to: output)
  }
}

/// Keep the latest availability evidence, including desktop outages such as a locked screen, not
/// thousands of duplicate reports and raw profiles.
private func preserveAvailability(_ report: ExecutionReport, artifacts: URL) throws {
  let output = artifacts.appending(path: "availability.json")
  let previous = try ArtifactLoader.existingReport(at: output)
  try TraceIO.save(report, to: output)
  if let previous, previous.needsAvailabilityRecovery,
    let run = previous.metadata["run"], UUID(uuidString: run) != nil,
    run != report.metadata["run"]
  {
    let directory = artifacts.appending(path: "runs/\(run)")
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
}

private func preserveSlowCandidate(
  _ report: ExecutionReport, identifier: String, artifacts: URL, current: [(Double, URL)]
) throws -> [(Double, URL)] {
  var next = current
  guard report.workloadDurationMilliseconds != nil,
    report.isBenchmarkSample
  else { return next }
  guard next.count < 20 || report.measuredMilliseconds > (next.map(\.0).min() ?? 0) else {
    return next
  }
  var slow = report
  slow.findings.append(
    ExecutionFinding(
      kind: .slow, signature: "campaign-tail",
      detail: "One of the 20 slowest sequences observed in this campaign."))
  let output = artifacts.appending(path: "findings/slow/\(identifier).json")
  try TraceIO.save(slow, to: output)
  next.append((report.measuredMilliseconds, output))
  next.sort { $0.0 > $1.0 }
  for (_, url) in next.dropFirst(20) {
    try FileManager.default.removeItem(at: url)
  }
  return Array(next.prefix(20))
}

private func loadSlowCandidates(_ artifacts: URL) throws -> [(Double, URL)] {
  try ArtifactLoader.slowCandidates(in: artifacts.appending(path: "findings/slow"), keeping: 20)
}

private func loadTraceOrReport(_ url: URL) throws -> (trace: FuzzTrace, report: ExecutionReport?) {
  let data = try Data(contentsOf: url)
  if let trace = try? JSONDecoder().decode(FuzzTrace.self, from: data) { return (trace, nil) }
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let report = try decoder.decode(ExecutionReport.self, from: data)
  return (report.trace, report)
}

private func printReport(_ report: ExecutionReport, output: URL) {
  outputLine(
    "actions completed/attempted: \(report.actionMilliseconds.count)/\(report.trace.actions.count)")
  outputLine("duration: \(Int(report.durationMilliseconds)) ms")
  outputLine("coverage regions: \(report.coverage.count)")
  for finding in report.findings { outputLine("\(finding.kind.rawValue): \(finding.detail)") }
  outputLine("report: \(output.path)")
}

private func outputLine(_ message: String) {
  try? FileHandle.standardOutput.write(contentsOf: Data("\(message)\n".utf8))
}
