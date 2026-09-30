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

  var binary: URL {
    app.appending(path: "Contents/MacOS/TypefaceOff")
  }
}

final class SequenceRunner {
  private let configuration: RunnerConfiguration
  private var explorer: ActionExplorer

  init(configuration: RunnerConfiguration, mutator: TraceMutator = TraceMutator()) {
    self.configuration = configuration
    explorer = ActionExplorer(mutator: mutator)
  }

  func execute(_ input: FuzzTrace, explorationActions: Int = 0) -> ExecutionReport {
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
        secondsSinceHeartbeat: TelemetryState.read(telemetryURL).lastHeartbeat.map { now - $0 },
        note: notes.isEmpty ? nil : notes.joined(separator: " "))
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
        && TelemetryState.read(telemetryURL).lastHeartbeat == nil
      {
        Thread.sleep(forTimeInterval: 0.05)
      }
      if application.hasExited {
        automationFailed = true
        findings.append(unexpectedExit(.launch))
      } else if TelemetryState.read(telemetryURL).lastHeartbeat == nil {
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
      for index in 0..<(input.actions.count + explorationActions) where !automationFailed {
        guard !application.hasExited else {
          findings.append(unexpectedExit(.beforeAction))
          break
        }
        let action: FuzzAction
        if index < input.actions.count {
          action = input.actions[index]
        } else {
          let discoveryStart = ProcessInfo.processInfo.systemUptime
          action = explorer.next(from: driver.availableActions(), using: &random)
          discoveryMilliseconds += (ProcessInfo.processInfo.systemUptime - discoveryStart) * 1000
        }
        executed.actions.append(action)
        try TraceIO.save(executed, to: runDirectory.appending(path: "executed.json"))
        let actionStart = ProcessInfo.processInfo.systemUptime
        lastActionStartedAt = actionStart
        do {
          try driver.perform(action)
        } catch {
          automationFailed = true
          if application.hasExited {
            findings.append(unexpectedExit(.duringAction, note: "Driver error: \(error)"))
          } else if let unavailable = error as? AvailabilityError {
            findings.append(unavailable.finding)
          } else {
            let available = driver.snapshot().prefix(100).joined(separator: ", ")
            findings.append(
              ExecutionFinding(
                kind: .automation, signature: String(describing: error),
                detail:
                  "Action \(executed.actions.count): \(error). Visible accessibility elements: \(available)"
              ))
          }
          break
        }
        actionTimes.append((ProcessInfo.processInfo.systemUptime - actionStart) * 1000)
        if action.delayMilliseconds > 0 {
          Thread.sleep(forTimeInterval: Double(action.delayMilliseconds) / 1000)
        }
        let telemetry = TelemetryState.read(telemetryURL)
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
          let telemetry = TelemetryState.read(telemetryURL)
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
        let telemetry = TelemetryState.read(telemetryURL)
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
      let heartbeat = TelemetryState.read(telemetryURL).lastHeartbeat,
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

    let telemetry = TelemetryState.read(telemetryURL)
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
    if let snapshot = telemetry.latestSnapshot,
      let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
    {
      metadata["final-snapshot"] = String(decoding: data, as: UTF8.self)
    }
    return ExecutionReport(
      trace: executed, startedAt: startedAt,
      durationMilliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1000,
      workloadDurationMilliseconds: workloadDurationMilliseconds,
      actionMilliseconds: actionTimes, coverage: coverage, countBuckets: buckets,
      findings: findings, exitStatus: exitStatus, terminatedByWatchdog: watchdog,
      metadata: metadata)
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
