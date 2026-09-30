import AppKit
import Foundation
import UIFuzzSupport

private enum RunnerError: Error, CustomStringConvertible {
  case launchFailed(String)
  case launchTimedOut

  var description: String {
    switch self {
    case .launchFailed(let detail): "Could not launch the app: \(detail)"
    case .launchTimedOut: "LaunchServices did not launch the app within 10 seconds"
    }
  }
}

private struct AppExited: Error {}

private final class LaunchResult: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Result<NSRunningApplication, Error>?

  func complete(application: NSRunningApplication?, error: Error?) {
    lock.withLock {
      if let application {
        value = .success(application)
      } else {
        value = .failure(error ?? RunnerError.launchFailed("no application was returned"))
      }
    }
  }

  func read() -> Result<NSRunningApplication, Error>? { lock.withLock { value } }
}

struct RunnerConfiguration {
  var app: URL
  var artifacts: URL
  var watchdogSeconds: TimeInterval = 10
  var completionSeconds: TimeInterval = 30
  var collectCoverage = true
  /// How long the app must be quiet before a live pick is discovered; zero disables the wait.
  var quiescenceSeconds: TimeInterval = 0.2

  var binary: URL {
    app.appending(path: "Contents/MacOS/TypefaceOff")
  }
}

final class SequenceRunner {
  private let configuration: RunnerConfiguration
  private var explorer: ActionExplorer
  /// Only a campaign sets it. Without one, no run can skip an action.
  var skipLedger: SkipLedger?

  init(configuration: RunnerConfiguration, mutator: TraceMutator = TraceMutator()) {
    self.configuration = configuration
    explorer = ActionExplorer(mutator: mutator)
  }

  func execute(_ input: FuzzTrace, explorationActions: Int = 0) -> ExecutionReport {
    precondition(explorationActions == 0 || skipLedger != nil)
    let startedAt = Date()
    let start = ProcessInfo.processInfo.systemUptime
    let runID = UUID().uuidString.lowercased()
    let runDirectory = configuration.artifacts.appending(path: "runs/\(runID)")
    // LLVM maps coverage counters into the raw profile, and those writes never reach a file
    // in a virtual machine's shared folder, so profiles start on the local disk.
    let profileDirectory = FileManager.default.temporaryDirectory.appending(
      path: "ui-fuzz-\(runID)")
    let telemetryURL = runDirectory.appending(path: "telemetry.jsonl")
    var findings: [ExecutionFinding] = []
    var actionTimes: [Double] = []
    var coverage = Set<String>()
    var buckets = Set<String>()
    var workloadStartedAt: TimeInterval?
    var workloadDurationMilliseconds: Double?
    var discoveryMilliseconds = 0.0
    let exitStatus: Int32? = nil
    var watchdog = false
    var automationFailed = false
    var launchedApplication: NSRunningApplication?
    var launchedProcessIdentifier: pid_t?
    var executed = input
    executed.actions = []
    var random = SplitMix64(seed: input.seed)
    let initialSession = DesktopSession.current()
    var lastActionStartedAt: TimeInterval?
    var quitMilliseconds: Double?
    var quitForced = false
    func unexpectedExit(_ phase: ExitPhase, note: String? = nil) -> ExecutionFinding {
      let now = ProcessInfo.processInfo.systemUptime
      var notes = note.map { [$0] } ?? []
      if let pid = launchedProcessIdentifier {
        notes.append(
          CrashReports.capture(
            pid: pid, processName: configuration.binary.lastPathComponent, since: startedAt,
            into: runDirectory))
      }
      return ProcessLiveness.unexpectedExitFinding(
        phase: phase, actionsDispatched: executed.actions.count,
        lastAction: executed.actions.last?.kind.rawValue,
        secondsSinceLastAction: lastActionStartedAt.map { now - $0 },
        secondsSinceHeartbeat: TelemetrySummary.read(telemetryURL).lastHeartbeat.map { now - $0 },
        note: notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    let clock = SystemClock()
    let quiescence = configuration.quiescenceSeconds
    var ledger = skipLedger ?? SkipLedger(policy: SkipPolicy(maximumPerRun: 0))
    ledger.beginRun()
    explorer.beginRun()
    var idleTail = TelemetryTail()
    var idleBudget = IdleBudget()
    var resolutions = ResolutionMetadata()
    resolutions.idleGated = explorationActions > 0 && quiescence > 0
    var skipSeconds = 0.0
    var readErrors = 0
    var diagnosticsWritten = 0
    var lastAttempts = 0
    var lastResolveSeconds = 0.0
    var driverLogHandle: FileHandle?
    var driverLogError: (any Error)?

    func log(_ event: DriverEvent) {
      guard driverLogError == nil else { return }
      do {
        let handle =
          try driverLogHandle ?? DriverLog.open(runDirectory.appending(path: "driver.jsonl"))
        driverLogHandle = handle
        try DriverLog.append(event, to: handle)
      } catch {
        driverLogError = error
      }
    }

    do {
      try initialSession.requireAvailable()
      try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
      try TraceIO.save(input, to: runDirectory.appending(path: "candidate.json"))
      try FileManager.default.createDirectory(
        at: profileDirectory, withIntermediateDirectories: true)
      let application = try launch(runDirectory: runDirectory, profileDirectory: profileDirectory)
      launchedApplication = application
      launchedProcessIdentifier = application.processIdentifier
      application.activate(options: [.activateAllWindows])
      let driver = try AXDriver(processIdentifier: application.processIdentifier)

      let startupDeadline = ProcessInfo.processInfo.systemUptime + configuration.watchdogSeconds
      while !application.hasExited && ProcessInfo.processInfo.systemUptime < startupDeadline
        && TelemetrySummary.read(telemetryURL).lastHeartbeat == nil
      {
        Thread.sleep(forTimeInterval: 0.05)
      }
      if application.hasExited {
        automationFailed = true
        findings.append(unexpectedExit(.launch))
      } else if TelemetrySummary.read(telemetryURL).lastHeartbeat == nil {
        automationFailed = true
        findings.append(
          ExecutionFinding(
            kind: .automation, signature: "startup-telemetry",
            detail:
              "The diagnostic app did not emit a main-thread heartbeat within \(configuration.watchdogSeconds) seconds."
          ))
      }

      if !automationFailed && !application.hasExited {
        try driver.waitForWorkbench()
        workloadStartedAt = ProcessInfo.processInfo.systemUptime
      }
      let telemetryBytes: (Int) -> Data = { TelemetryFile.bytes(at: telemetryURL, from: $0) }

      // Retries wait less when the app has been quiet for the last stretch.
      func quiet(since attemptedAt: TimeInterval) -> Bool {
        guard quiescence > 0 else { return true }
        return idleTail.refresh(read: telemetryBytes).isIdle(
          since: attemptedAt - quiescence, now: clock.now, quiescence: quiescence)
      }

      func begin(_ action: FuzzAction) throws {
        // The wait and discovery before a live pick can outlast a crash that an earlier action caused.
        guard !application.hasExited else { throw AppExited() }
        executed.actions.append(action)
        try TraceIO.save(executed, to: runDirectory.appending(path: "executed.json"))
        lastAttempts = 0
        lastResolveSeconds = 0
      }

      func resolveControl(_ request: ResolutionRequest, _ retry: ResolutionRetry) throws
        -> AXControl
      {
        let began = clock.now
        defer { lastResolveSeconds = clock.now - began }
        let result = try driver.resolve(request, retry: retry, idle: { quiet(since: $0) })
        lastAttempts = result.attempts
        readErrors += result.readErrors
        if let failure = result.resolution.failure(for: request) { throw failure }
        return AXControl(
          element: result.resolution.node!.element, step: result.resolution.step!,
          attempts: result.attempts)
      }

      func dumpFailure(
        action: FuzzAction, request: ResolutionRequest, error: String, attempts: Int,
        elapsed: TimeInterval, countedHere: Bool = true
      ) -> (dump: TreeDump, file: String?, telemetry: TelemetrySummary) {
        let began = clock.now
        let telemetry = TelemetrySummary.read(telemetryURL)
        let dump = driver.captureDump(
          TreeDump.Context(
            action: executed.actions.count, request: request, kind: action.kind, error: error,
            attempts: attempts, elapsedMilliseconds: Int(elapsed * 1000), telemetry: telemetry))
        diagnosticsWritten += 1
        var file: String? = "diagnostics-\(diagnosticsWritten).json"
        do {
          try TraceIO.save(dump, to: runDirectory.appending(path: file!))
          resolutions.recordDiagnostics(file!)
        } catch {
          findings.append(ResolutionFindings.sideFileFailure(.diagnostics, error: error))
          file = nil
        }
        if countedHere { skipSeconds += clock.now - began }
        return (dump, file, telemetry)
      }

      func terminalDetail(
        action: FuzzAction, request: ResolutionRequest, error: String, reason: String?,
        ambiguous: Bool, attempts: Int, elapsed: TimeInterval, stop: TerminalReason
      ) -> ResolutionFindings.Detail {
        let captured = dumpFailure(
          action: action, request: request, error: error, attempts: attempts, elapsed: elapsed)
        return ResolutionFindings.Detail(
          action: executed.actions.count, error: error, reason: reason, attempts: attempts,
          elapsedMilliseconds: Int(elapsed * 1000), telemetry: captured.telemetry,
          scope: captured.dump.scope,
          candidates: ambiguous ? captured.dump.candidates(for: request) : [],
          skipped: ledger.skips, stopReason: stop,
          diagnostics: captured.file.map { "runs/\(runID)/\($0)" },
          visibleElements: captured.dump.visibleElements())
      }

      var recordedCount = 0
      var liveCount = 0
      var lastReturn = workloadStartedAt ?? ProcessInfo.processInfo.systemUptime
      while !automationFailed {
        let isLive = recordedCount >= input.actions.count
        if isLive && liveCount >= explorationActions { break }
        guard !application.hasExited else {
          findings.append(unexpectedExit(.beforeAction))
          break
        }
        let slot: ResolvedSlot<AXControl>
        do {
          if isLive {
            slot = try resolveLiveSlot(
              slot: executed.actions.count + 1, since: lastReturn, ledger: &ledger, clock: clock,
              pick: { since in
                if quiescence > 0 {
                  let waited = IdleWait.run(
                    since: since, quiescence: quiescence, clock: clock, tail: &idleTail,
                    budget: &idleBudget, read: telemetryBytes)
                  log(
                    .idle(waited, uptime: clock.now, action: executed.actions.count + 1))
                }
                let discoveryStart = ProcessInfo.processInfo.systemUptime
                var stats: DiscoveryStats?
                let action = explorer.next(
                  from: driver.availableActions { stats = $0 }, using: &random)
                let discovered = (ProcessInfo.processInfo.systemUptime - discoveryStart) * 1000
                discoveryMilliseconds += discovered
                readErrors += stats?.readErrors ?? 0
                log(
                  DriverEvent(
                    uptime: clock.now, event: .discover, action: executed.actions.count + 1,
                    windows: stats?.windows, scope: stats?.scope, elements: stats?.elements,
                    elapsedMs: discovered))
                return action
              }, begin: begin, resolve: resolveControl,
              didSkip: { skipped, failure in
                let action = executed.actions[executed.actions.count - 1]
                explorer.exclude(action)
                log(
                  DriverEvent(
                    uptime: clock.now, event: .skip, action: skipped.slot, control: skipped.key,
                    attempts: lastAttempts, elapsedMs: lastResolveSeconds * 1000))
                var file: String?
                // resolveLiveSlot already counts the time spent in didSkip as skip time.
                if diagnosticsWritten == 0 {
                  file =
                    dumpFailure(
                      action: action,
                      request: ResolutionRequest(action, allowVisibleTieBreak: true),
                      error: failure.description, attempts: lastAttempts,
                      elapsed: lastResolveSeconds, countedHere: false
                    ).file
                }
                executed.actions.removeLast()
                try TraceIO.save(executed, to: runDirectory.appending(path: "executed.json"))
                return file
              })
          } else {
            slot = try resolveRecordedSlot(
              action: input.actions[recordedCount], begin: begin, resolve: resolveControl)
          }
        } catch is AppExited {
          findings.append(unexpectedExit(.beforeAction))
          break
        } catch let failure as SlotFailure {
          automationFailed = true
          skipSeconds += failure.skipSeconds
          if application.hasExited {
            findings.append(unexpectedExit(.beforeAction, note: "\(failure.underlying)"))
          } else if let unavailable = failure.underlying as? AvailabilityError {
            findings.append(unavailable.finding)
          } else {
            resolutions.stopReason = failure.reason
            let resolutionFailure = failure.underlying as? ResolutionFailure
            let error = String(describing: failure.underlying)
            let detail = terminalDetail(
              action: failure.action, request: failure.request, error: error,
              reason: resolutionFailure?.reason, ambiguous: resolutionFailure?.isAmbiguous == true,
              attempts: lastAttempts, elapsed: lastResolveSeconds, stop: failure.reason)
            findings.append(ResolutionFindings.finding(for: failure, detail: detail))
            log(
              DriverEvent(
                uptime: clock.now, event: .fail, action: executed.actions.count,
                control: failure.request.label, attempts: lastAttempts,
                pendingWork: detail.telemetry.pendingWork,
                openWork: detail.telemetry.openWorkKinds, elapsedMs: lastResolveSeconds * 1000))
          }
          break
        }
        skipSeconds += slot.skipSeconds
        let action = slot.action
        if let request = slot.request, let control = slot.target {
          log(
            DriverEvent(
              uptime: clock.now, event: .resolve, action: executed.actions.count,
              control: request.label, step: control.step, attempts: control.attempts,
              elapsedMs: lastResolveSeconds * 1000))
        }
        let actionStart = ProcessInfo.processInfo.systemUptime
        lastActionStartedAt = actionStart
        do {
          try driver.perform(action, on: slot.target?.element, idle: { quiet(since: $0) })
        } catch {
          automationFailed = true
          if application.hasExited {
            findings.append(unexpectedExit(.duringAction, note: "Driver error: \(error)"))
          } else if let unavailable = error as? AvailabilityError {
            findings.append(unavailable.finding)
          } else {
            resolutions.stopReason = .notSkippable
            let elapsed = ProcessInfo.processInfo.systemUptime - actionStart
            let text = String(describing: error)
            let detail = terminalDetail(
              action: action, request: ResolutionRequest(action, allowVisibleTieBreak: false),
              error: text, reason: (error as? DriverError)?.resolutionFailure?.reason,
              ambiguous: false, attempts: lastAttempts, elapsed: lastResolveSeconds,
              stop: .notSkippable)
            findings.append(
              ExecutionFinding(
                kind: .automation, signature: text, detail: ResolutionFindings.detail(detail)))
            log(
              DriverEvent(
                uptime: clock.now, event: .fail, action: executed.actions.count,
                control: slot.request?.label, pendingWork: detail.telemetry.pendingWork,
                openWork: detail.telemetry.openWorkKinds, elapsedMs: elapsed * 1000))
          }
          break
        }
        actionTimes.append(
          (ProcessInfo.processInfo.systemUptime - actionStart + lastResolveSeconds) * 1000)
        if let control = slot.target {
          resolutions.recordResolution(attempts: control.attempts, step: control.step)
        }
        if isLive { liveCount += 1 } else { recordedCount += 1 }
        lastReturn = ProcessInfo.processInfo.systemUptime
        if action.delayMilliseconds > 0 {
          Thread.sleep(forTimeInterval: Double(action.delayMilliseconds) / 1000)
        }
        let telemetry = TelemetrySummary.read(telemetryURL)
        if let heartbeat = telemetry.lastHeartbeat,
          ProcessInfo.processInfo.systemUptime - heartbeat > configuration.watchdogSeconds,
          !application.hasExited
        {
          watchdog = true
          findings.append(
            ExecutionFinding(
              kind: .hang, signature: "main-thread-heartbeat",
              detail: "No main-thread heartbeat for \(configuration.watchdogSeconds) seconds."))
          break
        }
      }

      if !application.hasExited && !watchdog && !automationFailed {
        let completionStart = ProcessInfo.processInfo.systemUptime
        var idleSince: TimeInterval?
        var reachedIdle = false
        while ProcessInfo.processInfo.systemUptime - completionStart
          < configuration.completionSeconds
        {
          if application.hasExited { break }
          let telemetry = TelemetrySummary.read(telemetryURL)
          let hasFreshHeartbeat = telemetry.lastHeartbeat.map { $0 >= completionStart } ?? false
          if telemetry.pendingWork == 0 && hasFreshHeartbeat {
            if idleSince == nil { idleSince = ProcessInfo.processInfo.systemUptime }
            if ProcessInfo.processInfo.systemUptime - (idleSince ?? 0) >= 0.2 {
              reachedIdle = true
              break
            }
          } else {
            idleSince = nil
          }
          if let heartbeat = telemetry.lastHeartbeat,
            ProcessInfo.processInfo.systemUptime - heartbeat > configuration.watchdogSeconds
          {
            watchdog = true
            findings.append(
              ExecutionFinding(
                kind: .hang, signature: "main-thread-heartbeat",
                detail: "The main thread stopped responding after the latest action."))
            break
          }
          Thread.sleep(forTimeInterval: 0.05)
        }
        let telemetry = TelemetrySummary.read(telemetryURL)
        if !reachedIdle && !watchdog && !application.hasExited {
          watchdog = true
          findings.append(
            ExecutionFinding(
              kind: .hang, signature: "completion-timeout",
              detail:
                "The latest UI work did not complete within \(configuration.completionSeconds) seconds."
            ))
        }
        for failure in telemetry.correctnessFailures {
          findings.append(
            ExecutionFinding(kind: .correctness, signature: failure, detail: failure))
        }
      }

      if let workloadStartedAt {
        workloadDurationMilliseconds =
          (ProcessInfo.processInfo.systemUptime - workloadStartedAt) * 1000 - discoveryMilliseconds
          - (idleBudget.spent + skipSeconds) * 1000
      }

      if application.hasExited && !findings.contains(where: { $0.kind == .crash }) {
        findings.append(unexpectedExit(.afterActions))
      }
    } catch {
      if launchedApplication?.hasExited == true {
        findings.append(
          unexpectedExit(workloadStartedAt == nil ? .launch : .beforeAction, note: "\(error)"))
      } else if let unavailable = error as? AvailabilityError {
        findings.append(unavailable.finding)
      } else {
        findings.append(
          ExecutionFinding(
            kind: .automation, signature: String(describing: error),
            detail: String(describing: error)
          ))
      }
    }

    // Accessibility timeouts must not conceal an app that stopped pumping its main run loop.
    if !watchdog, launchedApplication?.hasExited == false,
      let heartbeat = TelemetrySummary.read(telemetryURL).lastHeartbeat,
      ProcessInfo.processInfo.systemUptime - heartbeat > configuration.watchdogSeconds
    {
      watchdog = true
      findings.append(
        ExecutionFinding(
          kind: .hang, signature: "main-thread-heartbeat",
          detail: "The app stopped emitting heartbeats while the driver waited for its UI."))
    }
    let finalSession = DesktopSession.current()
    if let reason = finalSession.unavailableReason,
      !findings.contains(where: { $0.kind == .unavailable })
    {
      findings.append(
        AvailabilityError(signature: DesktopSession.unavailableSignature, detail: reason).finding)
    }

    if let application = launchedApplication {
      // Signalling a pid of 0 or -1 would reach whole process groups, so the pid that passed the
      // liveness check is the one signalled.
      let pid = application.processIdentifier
      let alreadyExited = !ProcessLiveness.isAlive(pid)
      if alreadyExited && !findings.contains(where: { $0.kind == .crash }) {
        findings.append(unexpectedExit(.afterActions))
      } else if !alreadyExited {
        let quitStart = ProcessInfo.processInfo.systemUptime
        if watchdog {
          kill(pid, SIGINT)
        } else {
          application.terminate()
        }
        if !ProcessLiveness.waitForExit(pid, timeout: 2) {
          quitForced = true
          application.forceTerminate()
          if !ProcessLiveness.waitForExit(pid, timeout: 2) {
            findings.append(
              ExecutionFinding(
                kind: .automation, signature: "quit-failed",
                detail: "The app was still running 2 seconds after forceTerminate()."))
          }
        }
        quitMilliseconds = (ProcessInfo.processInfo.systemUptime - quitStart) * 1000
      }
    }

    if FileManager.default.fileExists(atPath: profileDirectory.path) {
      do {
        if configuration.collectCoverage,
          let rawProfile = try FileManager.default.contentsOfDirectory(
            at: profileDirectory, includingPropertiesForKeys: nil
          ).first(where: { $0.pathExtension == "profraw" })
        {
          let result = try CoverageReader.read(
            rawProfile: rawProfile, binary: configuration.binary,
            workingDirectory: profileDirectory)
          coverage = result.regions
          buckets = result.countBuckets
        }
      } catch {
        findings.append(
          ExecutionFinding(
            kind: .automation, signature: "coverage-export",
            detail: "Could not export coverage: \(error)"))
      }
      do {
        for file in try FileManager.default.contentsOfDirectory(
          at: profileDirectory, includingPropertiesForKeys: nil)
        {
          try FileManager.default.moveItem(
            at: file, to: runDirectory.appending(path: file.lastPathComponent))
        }
        try FileManager.default.removeItem(at: profileDirectory)
      } catch {
        findings.append(
          ExecutionFinding(
            kind: .automation, signature: "profile-archive",
            detail: "Could not move the raw coverage profile into the run: \(error)"))
      }
    }

    do {
      try driverLogHandle?.close()
    } catch {
      driverLogError = driverLogError ?? error
    }
    if let driverLogError {
      findings.append(ResolutionFindings.sideFileFailure(.driverLog, error: driverLogError))
    }
    if skipLedger != nil { skipLedger = ledger }

    let telemetry = TelemetrySummary.read(telemetryURL)
    let explainedStartupFailure = findings.contains {
      ($0.kind == .automation && $0.signature == "startup-telemetry")
        || ($0.kind == .crash && $0.signature == "launch-termination")
    }
    if telemetry.events == 0 && launchedApplication != nil && !explainedStartupFailure {
      findings.append(
        ExecutionFinding(
          kind: .automation, signature: "missing-telemetry",
          detail: "The diagnostic app produced no telemetry events."))
    }
    for failure in telemetry.correctnessFailures
    where !findings.contains(where: { $0.kind == .correctness && $0.signature == failure }) {
      findings.append(ExecutionFinding(kind: .correctness, signature: failure, detail: failure))
    }
    if launchedApplication != nil {
      do {
        if let stderrFinding = try StderrScan.finding(
          logAt: runDirectory.appending(path: "stderr.log"), absentIsEmpty: telemetry.events == 0)
        {
          findings.append(stderrFinding)
        }
      } catch {
        findings.append(
          ExecutionFinding(
            kind: .automation, signature: "stderr-log", detail: "Could not scan stderr: \(error)"))
      }
    }
    var metadata = machineMetadata()
    for (key, value) in initialSession.metadata { metadata["initial-\(key)"] = value }
    for (key, value) in finalSession.metadata { metadata["final-\(key)"] = value }
    metadata["run"] = runID
    metadata["telemetry-events"] = String(telemetry.events)
    metadata["maximum-heartbeat-gap-ms"] = String(telemetry.maximumHeartbeatGap * 1000)
    metadata["process-model"] = "fresh"
    metadata["discovery-ms"] = String(discoveryMilliseconds)
    if let quitMilliseconds {
      metadata["quit-ms"] = String(quitMilliseconds)
      metadata["quit-forced"] = String(quitForced)
    }
    if let snapshot = telemetry.latestSnapshot { metadata["final-snapshot"] = snapshot }
    for (key, value) in resolutions.entries(
      skips: ledger.skips, idle: resolutions.idleGated ? idleBudget : nil)
    {
      metadata[key] = value
    }
    metadata["ax-read-errors"] = String(readErrors)
    return ExecutionReport(
      trace: executed, startedAt: startedAt,
      durationMilliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1000,
      workloadDurationMilliseconds: workloadDurationMilliseconds,
      actionMilliseconds: actionTimes, coverage: coverage, countBuckets: buckets,
      findings: ResolutionFindings.ordered(findings), exitStatus: exitStatus,
      terminatedByWatchdog: watchdog, metadata: metadata)
  }

  private func launch(runDirectory: URL, profileDirectory: URL) throws -> NSRunningApplication {
    let environment = [
      "TYPEFACEOFF_FUZZ_DIR": runDirectory.path,
      "LLVM_PROFILE_FILE": profileDirectory.appending(path: "%p%c.profraw").path,
    ]

    let openConfiguration = NSWorkspace.OpenConfiguration()
    openConfiguration.activates = true
    openConfiguration.addsToRecentItems = false
    openConfiguration.promptsUserIfNeeded = false
    openConfiguration.createsNewApplicationInstance = true
    openConfiguration.allowsRunningApplicationSubstitution = false
    openConfiguration.environment = environment
    let result = LaunchResult()
    NSWorkspace.shared.openApplication(
      at: configuration.app, configuration: openConfiguration
    ) { application, error in
      result.complete(application: application, error: error)
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 10
    while result.read() == nil && ProcessInfo.processInfo.systemUptime < deadline {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }
    guard let launchResult = result.read() else { throw RunnerError.launchTimedOut }
    return try launchResult.get()
  }

  private func machineMetadata() -> [String: String] {
    let process = ProcessInfo.processInfo
    return [
      "operating-system": process.operatingSystemVersionString,
      "processor-count": String(process.processorCount),
      "physical-memory": String(process.physicalMemory),
      "app": configuration.app.path,
    ]
  }
}

extension ResolutionFailure {
  fileprivate var isAmbiguous: Bool {
    if case .ambiguous = kind { true } else { false }
  }
}
