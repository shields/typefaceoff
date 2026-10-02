import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct MousePreparationTests {
  private static let target = MousePreparation.Hit(routing: .target, process: 10)
  private static let notification = MousePreparation.Hit(
    routing: .otherProcess, process: 20,
    bundleIdentifier: MousePreparation.notificationCenterBundleIdentifier)

  private struct InputFailure: Error, Equatable {}

  @Test func onlyAnExplicitOfferedCloseActionCanDismissANotification() {
    let close = "Name:Close\nTarget:0x123\nSelector:(null)"
    #expect(MousePreparation.closeAction(in: ["AXPress", "Name:Show Details", close]) == close)
    for actions in [
      [], ["AXPress"], ["Name:Close All\nTarget:0x123"], ["Name:Show Details\nTarget:0x123"],
      ["AXCancel"], ["Name:CloseSettings\nTarget:0x123"],
    ] {
      #expect(MousePreparation.closeAction(in: actions) == nil)
    }
  }

  @Test func anUnobstructedTargetNeedsNoInputOrWait() throws {
    let clock = FakeClock()
    let outcome = try MousePreparation.run(
      clock: clock, allowNotificationDismissal: true, hitTest: { Self.target },
      dismissNotification: { _ in
        Issue.record("Unexpected dismissal")
        return true
      },
      checkpoint: {})
    #expect(outcome.recovered)
    #expect(outcome.notificationDismissals == 0)
    #expect(clock.sleeps.isEmpty)
  }

  @Test func aNotificationIsDismissedOnceThenThePointIsTestedAgain() throws {
    let clock = FakeClock()
    var dismissals: [Int32] = []
    var hits = 0
    let outcome = try MousePreparation.run(
      clock: clock, allowNotificationDismissal: true, pollInterval: 0.25,
      hitTest: {
        hits += 1
        return clock.now < 0.5 ? Self.notification : Self.target
      },
      dismissNotification: {
        dismissals.append($0)
        return true
      }, checkpoint: {})
    #expect(dismissals == [20])
    #expect(hits == 3)
    #expect(outcome.hit == Self.target)
    #expect(outcome.notificationDismissals == 1)
    #expect(outcome.milliseconds == 500)
  }

  @Test func aPersistentNotificationStillFailsWithinTheBound() throws {
    let clock = FakeClock()
    var dismissals = 0
    let outcome = try MousePreparation.run(
      clock: clock, allowNotificationDismissal: true, timeout: 1,
      notificationSettleSeconds: 2, pollInterval: 0.75, hitTest: { Self.notification },
      dismissNotification: { _ in
        dismissals += 1
        return true
      }, checkpoint: {})
    #expect(dismissals == 1)
    #expect(!outcome.recovered)
    #expect(outcome.hit == Self.notification)
    #expect(outcome.milliseconds == 2000)
    #expect(clock.sleeps == [0.75, 0.75, 0.5])
  }

  @Test func hostCampaignsAndOtherApplicationsReceiveNoDismissal() throws {
    let dock = MousePreparation.Hit(
      routing: .otherProcess, process: 30, bundleIdentifier: "com.apple.dock")
    let unknown = MousePreparation.Hit(routing: .otherProcess, process: 40)
    for (allowed, hit) in [(false, Self.notification), (true, dock), (true, unknown)] {
      let clock = FakeClock()
      let outcome = try MousePreparation.run(
        clock: clock, allowNotificationDismissal: allowed, timeout: 1, pollInterval: 0.25,
        hitTest: { hit },
        dismissNotification: { _ in
          Issue.record("Unexpected dismissal")
          return true
        },
        checkpoint: {})
      #expect(!outcome.recovered)
      #expect(outcome.hit == hit)
      #expect(outcome.notificationDismissals == 0)
      #expect(outcome.milliseconds == 1000)
    }
  }

  @Test func anOffscreenPointFailsImmediatelyAndAnUnansweredHitCanRecover() throws {
    for routing in [MouseRouting.nothing, .unanswered] {
      let clock = FakeClock()
      let outcome = try MousePreparation.run(
        clock: clock, allowNotificationDismissal: true, pollInterval: 0.25,
        hitTest: {
          clock.now == 0 ? MousePreparation.Hit(routing: routing, process: 0) : Self.target
        },
        dismissNotification: { _ in
          Issue.record("Unexpected dismissal")
          return true
        },
        checkpoint: {})
      #expect(outcome.recovered == (routing == .unanswered))
      #expect(clock.sleeps.count == (routing == .unanswered ? 1 : 0))
    }
  }

  @Test func aVanishedNotificationIsNotDismissedOrRetriedIndefinitely() throws {
    let clock = FakeClock()
    var attempts = 0
    let outcome = try MousePreparation.run(
      clock: clock, allowNotificationDismissal: true, timeout: 1, pollInterval: 0.5,
      hitTest: { Self.notification },
      dismissNotification: { _ in
        attempts += 1
        return false
      }, checkpoint: {})
    #expect(attempts == 1)
    #expect(outcome.notificationDismissals == 0)
    #expect(outcome.milliseconds == 1000)
  }

  @Test func readingAndDismissalTimeCountAgainstTheDeadline() throws {
    let clock = FakeClock()
    let outcome = try MousePreparation.run(
      clock: clock, allowNotificationDismissal: true, timeout: 0.5,
      hitTest: {
        clock.advance(1)
        return Self.notification
      },
      dismissNotification: { _ in
        Issue.record("Unexpected dismissal")
        return true
      },
      checkpoint: {})
    #expect(!outcome.recovered)
    #expect(outcome.milliseconds == 1000)
    #expect(clock.sleeps.isEmpty)
  }

  @Test func aSleepThatOvershootsTheDeadlineStillReturnsAFailure() throws {
    let clock = OversleepingClock()
    let outcome = try MousePreparation.run(
      clock: clock, allowNotificationDismissal: false, timeout: 0.5, pollInterval: 0.5,
      hitTest: { Self.notification }, dismissNotification: { _ in false }, checkpoint: {})
    #expect(!outcome.recovered)
    #expect(outcome.milliseconds == 1500)
  }

  @Test func inputAndSessionFailuresPropagate() {
    #expect(throws: InputFailure.self) {
      try MousePreparation.run(
        clock: FakeClock(), allowNotificationDismissal: true, hitTest: { Self.notification },
        dismissNotification: { _ in throw InputFailure() }, checkpoint: {})
    }
    #expect(throws: InputFailure.self) {
      try MousePreparation.run(
        clock: FakeClock(), allowNotificationDismissal: true, hitTest: { Self.target },
        dismissNotification: { _ in true }, checkpoint: { throw InputFailure() })
    }
  }

  @Test func recoveryLogsIncludeTheFinalHitAndOutcome() throws {
    let event = DriverEvent(
      uptime: 10, event: .mouseRecovery, action: 3, attempts: 1, elapsedMs: 250,
      hitProcess: 10, hitBundleIdentifier: "com.typefaceoff.fuzz.coverage", recovered: true)
    let fields = try #require(
      JSONSerialization.jsonObject(with: Data(DriverLog.line(event).utf8)) as? [String: Any])
    #expect(fields["event"] as? String == "mouse-recovery")
    #expect(fields["hitProcess"] as? Int == 10)
    #expect(fields["recovered"] as? Bool == true)
    #expect(fields["hitBundleIdentifier"] as? String == "com.typefaceoff.fuzz.coverage")
  }

  private final class OversleepingClock: ResolutionClock {
    var now: TimeInterval = 0
    func sleep(_ seconds: TimeInterval) { now += seconds + 1 }
  }
}
