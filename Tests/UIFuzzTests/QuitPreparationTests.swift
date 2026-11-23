// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Testing

@testable import UIFuzzSupport

extension QuitPreparation.Overlay {
  fileprivate static let sheet = Self.located(role: "AXSheet", depth: 2)
  fileprivate static let menu = Self.located(role: "AXMenu", depth: 6)
}

@Suite struct QuitPreparationTests {
  struct KeyNotSent: Error, Equatable {}

  /// A stack of overlays with the one that receives input last. A layer starts closing when the
  /// `closingEscape`-th Escape reaches it, or never when that is nil, and is gone `closeDelay`
  /// seconds later. An Escape that reaches a layer already closing is dropped. Every check of the
  /// tree costs `checkSeconds`.
  final class FakeOverlay {
    struct Layer {
      let overlay: QuitPreparation.Overlay
      let closingEscape: Int?
      let closeDelay: TimeInterval
      var received = 0
      var closesAt: TimeInterval?

      init(
        _ overlay: QuitPreparation.Overlay = .sheet, closingEscape: Int? = 1,
        closeDelay: TimeInterval = 0.25
      ) {
        self.overlay = overlay
        self.closingEscape = closingEscape
        self.closeDelay = closeDelay
      }
    }

    let clock = FakeClock()
    let checkSeconds: TimeInterval
    let failingEscape: Int?
    private var layers: [Layer]
    private(set) var escapes = 0
    private(set) var escapeTimes: [TimeInterval] = []
    private(set) var checks = 0

    init(layers: [Layer], checkSeconds: TimeInterval = 0, failingEscape: Int? = nil) {
      self.layers = layers
      self.checkSeconds = checkSeconds
      self.failingEscape = failingEscape
    }

    convenience init(
      open: Bool = true, closingEscape: Int? = 1, closeDelay: TimeInterval = 0.25,
      checkSeconds: TimeInterval = 0, failingEscape: Int? = nil
    ) {
      self.init(
        layers: open ? [Layer(closingEscape: closingEscape, closeDelay: closeDelay)] : [],
        checkSeconds: checkSeconds, failingEscape: failingEscape)
    }

    /// A loop that ignores its bounds ends in a recorded issue instead of stalling the run.
    static let runaway = 1000

    func observe() -> QuitPreparation.Overlay? {
      checks += 1
      if checks > Self.runaway {
        Issue.record("The preparation kept checking the tree.")
        return nil
      }
      if checkSeconds > 0 { clock.advance(checkSeconds) }
      settle()
      return layers.last?.overlay
    }

    func dismiss() throws {
      if escapes >= Self.runaway {
        Issue.record("The preparation kept sending Escape.")
        throw KeyNotSent()
      }
      if failingEscape == escapes + 1 { throw KeyNotSent() }
      escapes += 1
      escapeTimes.append(clock.now)
      settle()
      guard let top = layers.indices.last else {
        Issue.record("An Escape went out with nothing open.")
        return
      }
      guard layers[top].closesAt == nil else { return }
      layers[top].received += 1
      if layers[top].received == layers[top].closingEscape {
        layers[top].closesAt = clock.now + layers[top].closeDelay
      }
    }

    private func settle() {
      while let closesAt = layers.last?.closesAt, clock.now >= closesAt {
        layers.removeLast()
      }
    }

    func prepare(
      maximumEscapes: Int = QuitPreparation.maximumEscapes,
      settleSeconds: TimeInterval = QuitPreparation.settleSeconds,
      pollInterval: TimeInterval = QuitPreparation.pollInterval
    ) -> QuitPreparation.Outcome {
      QuitPreparation.run(
        clock: clock, maximumEscapes: maximumEscapes, settleSeconds: settleSeconds,
        pollInterval: pollInterval, openOverlay: { self.observe() },
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

  @Test func aMenuOverASheetSendsTheSecondEscapeAsSoonAsTheMenuCloses() {
    let overlay = FakeOverlay(layers: [
      FakeOverlay.Layer(.sheet, closeDelay: 0.5), FakeOverlay.Layer(.menu, closeDelay: 0.25),
    ])
    let outcome = overlay.prepare(settleSeconds: 1, pollInterval: 0.125)
    #expect(outcome.escapes == 2)
    #expect(!outcome.overlayRemaining)
    #expect(outcome.failure == nil)
    #expect(overlay.escapeTimes == [0, 0.25])
    #expect(overlay.clock.sleeps == Array(repeating: 0.125, count: 6))
    #expect(outcome.milliseconds == 750)
  }

  @Test func theSecondEscapeDoesNotWaitOutTheDefaultWindow() {
    let overlay = FakeOverlay(layers: [
      FakeOverlay.Layer(.sheet, closeDelay: 0.25), FakeOverlay.Layer(.menu, closeDelay: 0.125),
    ])
    let outcome = overlay.prepare()
    #expect(outcome.escapes == 2)
    #expect(!outcome.overlayRemaining)
    let second = overlay.escapeTimes.last ?? 0
    #expect(second > 0.125 && second < 0.125 + 2 * QuitPreparation.pollInterval)
    #expect(outcome.milliseconds < QuitPreparation.settleSeconds * 1000)
  }

  @Test func anEscapeThatChangesNothingWaitsTheWindowAndThenTheNextLayerGoesAtOnce() {
    let overlay = FakeOverlay(layers: [
      FakeOverlay.Layer(.sheet, closeDelay: 0.5),
      FakeOverlay.Layer(.menu, closingEscape: 2, closeDelay: 0.25),
    ])
    let outcome = overlay.prepare(settleSeconds: 1, pollInterval: 0.25)
    #expect(outcome.escapes == 3)
    #expect(!outcome.overlayRemaining)
    #expect(overlay.escapeTimes == [0, 1, 1.25])
    #expect(outcome.milliseconds == 1750)
  }

  @Test func anEscapeThatChangesNothingIsSentAgainAfterTheWindowPasses() {
    let overlay = FakeOverlay(closingEscape: 2, closeDelay: 0.25)
    let outcome = overlay.prepare(settleSeconds: 1, pollInterval: 0.25)
    #expect(outcome.escapes == 2)
    #expect(!outcome.overlayRemaining)
    #expect(overlay.escapeTimes == [0, 1])
    #expect(overlay.clock.sleeps == [0.25, 0.25, 0.25, 0.25, 0.25])
    #expect(outcome.milliseconds == 1250)
  }

  @Test func aLayerReplacedByOneThatLooksTheSameWaitsOutTheWindow() {
    let overlay = FakeOverlay(layers: [FakeOverlay.Layer(.sheet), FakeOverlay.Layer(.sheet)])
    let outcome = overlay.prepare(settleSeconds: 1, pollInterval: 0.25)
    #expect(outcome.escapes == 2)
    #expect(!outcome.overlayRemaining)
    #expect(overlay.escapeTimes == [0, 1])
    #expect(outcome.milliseconds == 1250)
  }

  @Test func aLayerReplacedByOneWithAnotherRoleOrDepthIsSeenAtOnce() {
    let replacements: [QuitPreparation.Overlay] = [
      .located(role: "AXSheet", depth: 4), .located(role: "AXPopover", depth: 2), .menu,
    ]
    for replacement in replacements {
      let overlay = FakeOverlay(layers: [
        FakeOverlay.Layer(replacement), FakeOverlay.Layer(.sheet),
      ])
      let outcome = overlay.prepare(settleSeconds: 1, pollInterval: 0.25)
      #expect(outcome.escapes == 2, "\(replacement)")
      #expect(!outcome.overlayRemaining, "\(replacement)")
      #expect(overlay.escapeTimes == [0, 0.25], "\(replacement)")
      #expect(outcome.milliseconds == 500, "\(replacement)")
    }
  }

  @Test func anOverlayThatCannotBeLocatedIsDismissedLikeAnyOther() {
    let overlay = FakeOverlay(layers: [FakeOverlay.Layer(.unlocated)])
    let outcome = overlay.prepare()
    #expect(outcome.escapes == 1)
    #expect(!outcome.overlayRemaining)
    #expect(outcome.milliseconds == 250)
  }

  @Test func anOverlayThatCannotBeLocatedIsNeverEvidenceOfAChange() {
    let transitions: [(top: QuitPreparation.Overlay, below: QuitPreparation.Overlay)] = [
      (.unlocated, .unlocated), (.sheet, .unlocated), (.unlocated, .sheet),
    ]
    for (top, below) in transitions {
      let overlay = FakeOverlay(layers: [FakeOverlay.Layer(below), FakeOverlay.Layer(top)])
      let outcome = overlay.prepare(settleSeconds: 1, pollInterval: 0.25)
      #expect(outcome.escapes == 2, "\(top) over \(below)")
      #expect(!outcome.overlayRemaining, "\(top) over \(below)")
      #expect(overlay.escapeTimes == [0, 1], "\(top) over \(below)")
    }
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

  @Test func moreLayersThanEscapesLeavesTheRestOpenWithoutWaiting() {
    let depths = 2..<6
    let overlay = FakeOverlay(
      layers: depths.map { FakeOverlay.Layer(.located(role: "AXSheet", depth: $0)) })
    let outcome = overlay.prepare(settleSeconds: 1, pollInterval: 0.25)
    #expect(outcome.escapes == QuitPreparation.maximumEscapes)
    #expect(overlay.escapes == QuitPreparation.maximumEscapes)
    #expect(outcome.overlayRemaining)
    #expect(outcome.failure == nil)
    #expect(overlay.escapeTimes == [0, 0.25, 0.5])
    #expect(outcome.milliseconds == 750)
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

  @Test func theDurationIsMeasuredFromTheStartOfThePreparation() {
    let overlay = FakeOverlay(closeDelay: 0.25)
    overlay.clock.advance(1000)
    #expect(overlay.prepare().milliseconds == 250)
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

  @Test func aKeyThatCannotBeSentAfterTheFirstLayerClosedKeepsTheLayerBelow() {
    let overlay = FakeOverlay(
      layers: [FakeOverlay.Layer(.sheet), FakeOverlay.Layer(.menu)], failingEscape: 2)
    let outcome = overlay.prepare(settleSeconds: 1, pollInterval: 0.25)
    #expect(outcome.escapes == 1)
    #expect(outcome.overlayRemaining)
    #expect(outcome.failure as? KeyNotSent == KeyNotSent())
    #expect(overlay.escapeTimes == [0])
    #expect(overlay.clock.sleeps == [0.25])
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

  @Test func aModalRootIsObservedByItsRoleAndDepth() {
    #expect(
      QuitPreparation.Overlay(ModalSelection(root: [0, 4], rootRole: "AXSheet"))
        == .located(role: "AXSheet", depth: 2))
    #expect(
      QuitPreparation.Overlay(ModalSelection(root: [0, 1, 2, 3, 4, 5], rootRole: "AXMenu"))
        == .menu)
    #expect(
      QuitPreparation.Overlay(ModalSelection(root: [1], rootRole: nil))
        == .located(role: nil, depth: 1))
  }

  @Test func anOverlayWithoutARootIsObservedOnlyWhenItHasFocus() {
    #expect(QuitPreparation.Overlay(ModalSelection(root: nil, unlocated: true)) == .unlocated)
    #expect(QuitPreparation.Overlay(ModalSelection(root: nil)) == nil)
  }

  struct ChangeRow: CustomStringConvertible {
    var name: String
    var layer: QuitPreparation.Overlay
    var observation: QuitPreparation.Overlay?
    var changed: Bool
    var description: String { name }
  }

  static let changeRows = [
    ChangeRow(name: "nothing is open", layer: .sheet, observation: nil, changed: true),
    ChangeRow(
      name: "an unlocated layer closed", layer: .unlocated, observation: nil, changed: true),
    ChangeRow(name: "the same sheet", layer: .sheet, observation: .sheet, changed: false),
    ChangeRow(
      name: "the same unlocated overlay", layer: .unlocated, observation: .unlocated, changed: false
    ),
    ChangeRow(
      name: "another depth", layer: .sheet, observation: .located(role: "AXSheet", depth: 4),
      changed: true),
    ChangeRow(
      name: "another role", layer: .sheet, observation: .located(role: "AXPopover", depth: 2),
      changed: true),
    ChangeRow(
      name: "a role that appeared", layer: .located(role: nil, depth: 2), observation: .sheet,
      changed: true),
    ChangeRow(
      name: "a located layer, then an unlocated one", layer: .sheet, observation: .unlocated,
      changed: false),
    ChangeRow(
      name: "an unlocated layer, then a located one", layer: .unlocated, observation: .sheet,
      changed: false),
  ]

  @Test func aLayerChangedOnlyWhenItClosedOrAnotherLocatedOneTookItsPlace() {
    for row in Self.changeRows {
      #expect(row.layer.isChanged(by: row.observation) == row.changed, "\(row)")
    }
  }
}
