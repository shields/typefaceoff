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

  @Option(help: "Minimum free disk space in MiB on the artifact and temporary volumes.")
  var minimumFreeSpaceMib: UInt64 = 512

  mutating func validate() throws {
    guard watchdog > 0, completionTimeout > 0 else {
      throw ValidationError("Watchdog and completion timeouts must be positive.")
    }
    guard minimumFreeSpaceMib <= UInt64.max / 1_048_576 else {
      throw ValidationError("--minimum-free-space-mib is too large.")
    }
  }

  var runnerConfiguration: RunnerConfiguration {
    RunnerConfiguration(
      app: URL(fileURLWithPath: app), artifacts: URL(fileURLWithPath: artifacts),
      watchdogSeconds: watchdog, completionSeconds: completionTimeout,
      minimumFreeSpaceBytes: minimumFreeSpaceMib * 1_048_576)
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

  @Option(
    help:
      "Milliseconds the app must be quiet before a live exploration action is discovered, at most 1000. Zero disables the wait."
  )
  var quiescenceMs = 200

  @Option(
    help:
      "Live exploration actions one execution may skip when their control cannot be found. Zero ends the execution at the first one."
  )
  var maxSkipsPerRun = 5

  @Flag(help: "Discard the skip ledger, which counts failures to find controls across executions.")
  var resetSkipLedger = false

  mutating func run() throws {
    guard maxActions > 0 else { throw ValidationError("--max-actions must be positive.") }
    guard maxTextUnits >= 0 else { throw ValidationError("--max-text-units cannot be negative.") }
    // No wait outlasts `IdleWait.beforeDiscovery`, so a longer quiet period mostly times out.
    let longestQuiescenceMs = Int(IdleWait.beforeDiscovery * 1000)
    guard (0...longestQuiescenceMs).contains(quiescenceMs) else {
      throw ValidationError("--quiescence-ms must be between 0 and \(longestQuiescenceMs).")
    }
    guard maxSkipsPerRun >= 0 else {
      throw ValidationError("--max-skips-per-run cannot be negative.")
    }
    AXDriver.waitForPermissions()
    outputLine("running startup self-test")
    StartupSelfTest.run(configuration: common.runnerConfiguration)
    outputLine("startup self-test passed")
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
    var corpus = try ArtifactLoader.corpus(in: corpusURL).map(mutator.constrained)
    if corpus.isEmpty {
      corpus = mutator.initialCorpus(seed: campaignSeed)
      for (index, trace) in corpus.enumerated() {
        try TraceIO.save(trace, to: corpusURL.appending(path: "seed-\(index).json"))
      }
    }
    var state = try ArtifactLoader.corpusState(at: artifactURL.appending(path: "campaign.json"))
    var runnerConfiguration = common.runnerConfiguration
    runnerConfiguration.quiescenceSeconds = Double(quiescenceMs) / 1000
    let runner = SequenceRunner(configuration: runnerConfiguration, mutator: mutator)
    let ledgerURL = artifactURL.appending(path: "skip-ledger.json")
    let opened = SkipLedger.opening(
      existing: resetSkipLedger ? SkipLedger() : try SkipLedger.load(from: ledgerURL),
      appFingerprint: try appFingerprint(runnerConfiguration.binary), reset: resetSkipLedger,
      policy: SkipPolicy(maximumPerRun: maxSkipsPerRun))
    if let notice = opened.notice { outputLine(notice) }
    runner.skipLedger = opened.ledger
    var slowest = try loadSlowCandidates(artifactURL)
    var findingArchive = try FindingArchive.open(in: artifactURL)
    // An availability report that cannot be decoded would otherwise stop the campaign at its
    // first desktop outage.
    _ = try ArtifactLoader.existingReport(at: artifactURL.appending(path: "availability.json"))
    var backoff = CampaignBackoff()
    var launchFailures = LaunchFailureStreak()
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
      let ledgerBeforeRun = runner.skipLedger
      let report = try runner.execute(
        trace, explorationActions: trace.origin == "exploration" ? min(maxActions, 32) : 0)
      // The trace of an execution cut short by an outage runs again, so its counts are dropped.
      if report.needsAvailabilityRecovery { runner.skipLedger = ledgerBeforeRun }
      try runner.skipLedger?.save(to: ledgerURL)
      if report.needsAvailabilityRecovery {
        try ArtifactRetention.discardCoverageArtifacts(for: report, in: artifactURL)
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
      if !delta.isInteresting {
        try ArtifactRetention.discardCoverageArtifacts(for: report, in: artifactURL)
      }
      let identifier = String(format: "%08d-%016llx", state.executions, trace.seed)
      if delta.isInteresting, let admitted = CorpusAdmission.trace(for: report) {
        corpus.append(admitted)
        try TraceIO.save(admitted, to: corpusURL.appending(path: "\(identifier).json"))
      }
      let findingFiles = try findingArchive.preserve(report, execution: identifier)
      slowest = try preserveSlowCandidate(
        report, identifier: identifier, artifacts: artifactURL, current: slowest)
      try saveState(state, to: artifactURL.appending(path: "campaign.json"))
      let findingKinds = report.findings.map(\.kind.rawValue).joined(separator: ",")
      let inputs = Dictionary(grouping: report.trace.actions, by: \.kind.rawValue)
        .sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.count)" }.joined(separator: ",")
      let skips = Int(report.metadata["skipped-actions"] ?? "") ?? 0
      outputLine(
        "#\(state.executions) mode=\(trace.origin) actions=\(report.actionMilliseconds.count)/\(report.trace.actions.count)\(ResolutionMetadata.progressSuffix(skips: skips)) measured-ms=\(Int(report.measuredMilliseconds)) total-ms=\(Int(report.durationMilliseconds)) "
          + "new=\(delta.regions.count)/\(delta.countBuckets.count)"
          + " inputs=\(inputs)"
          + (findingKinds.isEmpty ? "" : " findings=\(findingKinds)"))
      try launchFailures.record(
        report,
        findingFile: findingFiles[
          FindingIdentity(
            kind: .crash, signature: ProcessLiveness.launchTerminationSignature)
        ]?.path ?? "")
    }
    outputLine("stopped after \(state.executions) executions; corpus has \(corpus.count) entries")
    if let lines = runner.skipLedger?.summary(), !lines.isEmpty {
      outputLine("controls that failed to resolve most often:")
      for line in lines { outputLine("  \(line)") }
    }
  }
}

struct Replay: ParsableCommand {
  @OptionGroup var common: CommonOptions
  @Option(name: .customLong("case"), help: "Trace or execution report to replay.")
  var casePath: String

  mutating func run() throws {
    AXDriver.waitForPermissions()
    let trace = try loadTraceOrReport(URL(fileURLWithPath: casePath)).trace
    let report = try SequenceRunner(configuration: common.runnerConfiguration).execute(trace)
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
    guard let target = original.report?.findings.first(where: { !$0.isSideFileFailure }) else {
      throw ValidationError(
        "Minimization requires an execution report containing a finding other than a failure to write one of the fuzzer's own files."
      )
    }
    guard !target.signature.hasPrefix(ResolutionSignature.persistent) else {
      throw ValidationError(
        "A persistent stale control finding summarizes many executions, so one run cannot reproduce it."
      )
    }
    let baseline = original.report?.measuredMilliseconds
    let minimized = try TraceReducer.reduce(original.trace) { actions in
      var candidate = original.trace
      candidate.actions = actions
      if target.kind == .slow, let baseline {
        let reports = try (0..<3).map { _ in try runner.execute(candidate) }
        guard reports.allSatisfy(\.isBenchmarkSample) else { return false }
        let values = reports.map(\.measuredMilliseconds)
        return (Statistics.median(values) ?? 0) >= baseline * 0.9
      }
      let report = try runner.execute(candidate)
      return report.findings.contains { $0.reproduces(target) }
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
    let traces = try ArtifactLoader.corpus(in: URL(fileURLWithPath: corpus))
    guard !traces.isEmpty else { throw ValidationError("No traces in \(corpus).") }
    var results: [[String: Any]] = []
    var failedSamples = 0
    for trace in traces {
      let reports = try (0..<repetitions).map { _ in try runner.execute(trace) }
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

private func appFingerprint(_ binary: URL) throws -> String {
  let attributes = try FileManager.default.attributesOfItem(atPath: binary.path)
  guard let modified = attributes[.modificationDate] as? Date,
    let size = attributes[.size] as? NSNumber
  else { throw ValidationError("Cannot read the modification time and size of \(binary.path).") }
  return SkipLedger.fingerprint(
    path: binary.path, modified: modified.timeIntervalSince1970, size: size.intValue)
}

private func saveState(_ state: CorpusState, to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(state).write(to: url, options: .atomic)
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

private let slowCandidateLimit = 20

private func preserveSlowCandidate(
  _ report: ExecutionReport, identifier: String, artifacts: URL, current: [(Double, URL)]
) throws -> [(Double, URL)] {
  var next = current
  guard report.isBenchmarkSample else { return next }
  guard
    next.count < slowCandidateLimit || report.measuredMilliseconds > (next.map(\.0).min() ?? 0)
  else { return next }
  var slow = report
  slow.coverage = []
  slow.countBuckets = []
  slow.findings.append(
    ExecutionFinding(
      kind: .slow, signature: "campaign-tail",
      detail: "One of the \(slowCandidateLimit) slowest sequences observed in this campaign."))
  let output = artifacts.appending(path: "findings/slow/\(identifier).json")
  try TraceIO.save(slow, to: output)
  next.append((report.measuredMilliseconds, output))
  next.sort { $0.0 > $1.0 }
  for (_, url) in next.dropFirst(slowCandidateLimit) {
    try FileManager.default.removeItem(at: url)
  }
  return Array(next.prefix(slowCandidateLimit))
}

private func loadSlowCandidates(_ artifacts: URL) throws -> [(Double, URL)] {
  try ArtifactLoader.slowCandidates(
    in: artifacts.appending(path: "findings/slow"), keeping: slowCandidateLimit)
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
