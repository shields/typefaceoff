import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct QuitPreparationTests {
  struct KeyNotSent: Error, Equatable {}

  /// Closes `closeDelay` seconds after the `closingEscape`-th Escape, or never when that is nil.
  /// Every check of the tree costs `checkSeconds`.
  final class FakeOverlay {
    let clock = FakeClock()
    let closingEscape: Int?
    let closeDelay: TimeInterval
    let checkSeconds: TimeInterval
    let failingEscape: Int?
    private var closesAt: TimeInterval
    private(set) var escapes = 0
    private(set) var checks = 0

    init(
      open: Bool = true, closingEscape: Int? = 1, closeDelay: TimeInterval = 0.25,
      checkSeconds: TimeInterval = 0, failingEscape: Int? = nil
    ) {
      self.closingEscape = closingEscape
      self.closeDelay = closeDelay
      self.checkSeconds = checkSeconds
      self.failingEscape = failingEscape
      closesAt = open ? .infinity : 0
    }

    func isOpen() -> Bool {
      checks += 1
      if checkSeconds > 0 { clock.advance(checkSeconds) }
      return clock.now < closesAt
    }

    func dismiss() throws {
      if failingEscape == escapes + 1 { throw KeyNotSent() }
      escapes += 1
      if escapes == closingEscape { closesAt = clock.now + closeDelay }
    }

    func prepare(
      maximumEscapes: Int = QuitPreparation.maximumEscapes,
      settleSeconds: TimeInterval = QuitPreparation.settleSeconds,
      pollInterval: TimeInterval = QuitPreparation.pollInterval
    ) -> QuitPreparation.Outcome {
      QuitPreparation.run(
        clock: clock, maximumEscapes: maximumEscapes, settleSeconds: settleSeconds,
        pollInterval: pollInterval, isOverlayOpen: { self.isOpen() },
        dismiss: { try self.dismiss() }
      )
    }
  }

  @Test func withNothingOpenNothingIsSentAndNothingWaitedFor() {
    let overlay = FakeOverlay(open: false)
    let outcome = overlay.prepare()
    #expect(outcome.escapes == 0)
    #expect(!outcome.overlayRemaining)
    #expect(outcome.failure == nil)
    #expect(overlay.checks == 1)
    #expect(overlay.clock.sleeps.isEmpty)
    #expect(
      outcome.metadata == [
        "quit-overlays-dismissed": "0", "quit-overlay-remaining": "false",
        "quit-dismiss-ms": "0.0",
      ])
  }

  @Test func aSheetThatClosesSlowlyIsPolledForRatherThanSleptThrough() {
    let overlay = FakeOverlay(closeDelay: 0.25)
    let outcome = overlay.prepare()
    #expect(outcome.escapes == 1)
    #expect(!outcome.overlayRemaining)
    #expect(overlay.escapes == 1)
    #expect(overlay.clock.sleeps.count == 5)
    #expect(overlay.clock.sleeps.allSatisfy { $0 == QuitPreparation.pollInterval })
    #expect(outcome.milliseconds == 250)
  }

  @Test func anEscapeThatChangesNothingIsSentAgainAfterTheWindowPasses() {
    let overlay = FakeOverlay(closingEscape: 2, closeDelay: 0.25)
    let outcome = overlay.prepare(settleSeconds: 1, pollInterval: 0.25)
    #expect(outcome.escapes == 2)
    #expect(!outcome.overlayRemaining)
    #expect(overlay.clock.sleeps == [0.25, 0.25, 0.25, 0.25, 0.25])
    #expect(outcome.milliseconds == 1250)
  }

  @Test func anOverlayThatNeverClosesIsReportedAfterTheLastEscape() {
    let overlay = FakeOverlay(closingEscape: nil)
    let outcome = overlay.prepare(settleSeconds: 0.5, pollInterval: 0.125)
    #expect(outcome.escapes == QuitPreparation.maximumEscapes)
    #expect(overlay.escapes == QuitPreparation.maximumEscapes)
    #expect(outcome.overlayRemaining)
    #expect(outcome.failure == nil)
    #expect(overlay.clock.sleeps.count == 4 * QuitPreparation.maximumEscapes)
    #expect(outcome.milliseconds == 1500)
    #expect(outcome.metadata["quit-overlays-dismissed"] == "3")
    #expect(outcome.metadata["quit-overlay-remaining"] == "true")
    #expect(outcome.metadata["quit-dismiss-ms"] == "1500.0")
  }

  @Test func theDefaultsBoundTheWaitToUnderTwoSecondsOfPolling() {
    let overlay = FakeOverlay(closingEscape: nil)
    let outcome = overlay.prepare()
    #expect(outcome.escapes == 3)
    #expect(outcome.overlayRemaining)
    #expect(overlay.clock.sleeps.count == 30)
    #expect(outcome.milliseconds == 1500)
  }

  @Test func timeSpentReadingTheTreeCountsAgainstTheWindow() {
    let overlay = FakeOverlay(closingEscape: nil, checkSeconds: 0.25)
    let outcome = overlay.prepare(maximumEscapes: 1, settleSeconds: 1, pollInterval: 0.25)
    #expect(overlay.clock.sleeps == [0.25, 0.25])
    #expect(overlay.checks == 3)
    #expect(outcome.milliseconds == 1250)
    #expect(outcome.overlayRemaining)
  }

  @Test func theLastSleepStopsAtTheEndOfTheWindow() {
    let overlay = FakeOverlay(closingEscape: nil)
    let outcome = overlay.prepare(maximumEscapes: 1, settleSeconds: 1, pollInterval: 0.75)
    #expect(overlay.clock.sleeps == [0.75, 0.25])
    #expect(outcome.milliseconds == 1000)
  }

  @Test func aKeyThatCannotBeSentEndsTheAttemptsAndKeepsTheReason() {
    let overlay = FakeOverlay(closingEscape: nil, failingEscape: 2)
    let outcome = overlay.prepare(settleSeconds: 0.25, pollInterval: 0.25)
    #expect(outcome.escapes == 1)
    #expect(outcome.overlayRemaining)
    #expect(outcome.failure as? KeyNotSent == KeyNotSent())
    #expect(overlay.escapes == 1)
    #expect(overlay.clock.sleeps == [0.25])

    let first = FakeOverlay(failingEscape: 1)
    let none = first.prepare()
    #expect(none.escapes == 0)
    #expect(none.overlayRemaining)
    #expect(none.failure is KeyNotSent)
    #expect(first.clock.sleeps.isEmpty)
  }

  @Test func aLimitOfZeroOnlyReportsWhatIsOpen() {
    let overlay = FakeOverlay()
    let outcome = overlay.prepare(maximumEscapes: 0)
    #expect(outcome.escapes == 0)
    #expect(outcome.overlayRemaining)
    #expect(overlay.escapes == 0)
    #expect(overlay.checks == 1)
  }

  @Test func theMetadataKeepsTheFractionOfAMillisecond() {
    let outcome = QuitPreparation.Outcome(
      escapes: 2, overlayRemaining: true, milliseconds: 312.5, failure: nil)
    #expect(
      outcome.metadata == [
        "quit-overlays-dismissed": "2", "quit-overlay-remaining": "true",
        "quit-dismiss-ms": "312.5",
      ])
  }
}
