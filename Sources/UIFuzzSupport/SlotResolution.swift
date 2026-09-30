import Foundation

public struct ResolvedSlot<Target> {
  public var action: FuzzAction
  /// `nil` when the action needs no control.
  public var request: ResolutionRequest?
  public var target: Target?
  /// Time spent resolving and reporting the picks that were skipped before this one.
  public var skipSeconds: TimeInterval
}

/// `underlying` is the error to report and may be an availability error that the caller has to
/// recognize.
public struct SlotFailure: Error {
  public var action: FuzzAction
  public var request: ResolutionRequest
  public var underlying: any Error
  public var reason: TerminalReason
  public var skipSeconds: TimeInterval
}

/// Picks and resolves one live exploration action, skipping picks whose control cannot be found
/// while the ledger allows it. `begin` records an action before it is resolved and `didSkip`
/// takes it back and may return the name of a diagnostics file. The ledger sees every resolve
/// and every skip, so callers never touch it. `pick` receives the time from which the app must
/// have been quiet: `since` at first, then the time of the latest skip.
public func resolveLiveSlot<Target>(
  slot: Int, since: TimeInterval, ledger: inout SkipLedger, clock: some ResolutionClock,
  pick: (_ since: TimeInterval) -> FuzzAction, begin: (FuzzAction) throws -> Void,
  resolve: (ResolutionRequest, ResolutionRetry) throws -> Target,
  didSkip: (SkippedAction, ResolutionFailure) throws -> String?
) throws -> ResolvedSlot<Target> {
  var since = since
  var skipSeconds = 0.0
  var resolved: ResolvedSlot<Target>?
  repeat {
    let action = pick(since)
    try begin(action)
    let started = clock.now
    guard action.kind.needsTarget else {
      ledger.succeeded(nil)
      resolved = ResolvedSlot(
        action: action, request: nil, target: nil, skipSeconds: skipSeconds)
      continue
    }
    let request = ResolutionRequest(action, allowVisibleTieBreak: true)
    do {
      let target = try resolve(request, .live)
      ledger.succeeded(request)
      resolved = ResolvedSlot(
        action: action, request: request, target: target, skipSeconds: skipSeconds)
    } catch let failure as ResolutionFailure where failure.isSkippable {
      switch ledger.failed(
        request, slot: slot, kind: action.kind.rawValue, signature: failure.description)
      {
      case .skip(let skipped):
        if let file = try didSkip(skipped, failure) { ledger.recordDiagnostics(file) }
        since = clock.now
        skipSeconds += since - started
      case .terminal(let reason):
        throw SlotFailure(
          action: action, request: request, underlying: failure, reason: reason,
          skipSeconds: skipSeconds)
      }
    } catch {
      throw SlotFailure(
        action: action, request: request, underlying: error, reason: .notSkippable,
        skipSeconds: skipSeconds)
    }
  } while resolved == nil
  return resolved!
}

/// Resolves one action of a recorded trace. It has no ledger, so a failure is always terminal:
/// replays, minimization, and mutation runs must reproduce a missing control, not step around it.
public func resolveRecordedSlot<Target>(
  action: FuzzAction, begin: (FuzzAction) throws -> Void,
  resolve: (ResolutionRequest, ResolutionRetry) throws -> Target
) throws -> ResolvedSlot<Target> {
  try begin(action)
  guard action.kind.needsTarget else {
    return ResolvedSlot(action: action, request: nil, target: nil, skipSeconds: 0)
  }
  let request = ResolutionRequest(action, allowVisibleTieBreak: false)
  do {
    let target = try resolve(request, .recorded)
    return ResolvedSlot(action: action, request: request, target: target, skipSeconds: 0)
  } catch {
    throw SlotFailure(
      action: action, request: request, underlying: error, reason: .recordedAction,
      skipSeconds: 0)
  }
}
