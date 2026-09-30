import Foundation

/// AppKit drops a quit request that arrives while a sheet is open, and an open menu delays it, so
/// the driver closes what a run leaves open before it asks the app to quit.
public enum QuitPreparation {
  public static let maximumEscapes = 3
  /// A sheet needs a moment to close after the key that dismisses it, and a quit sent before it
  /// has gone is dropped.
  public static let settleSeconds: TimeInterval = 0.5
  public static let pollInterval: TimeInterval = 0.05

  public struct Outcome {
    /// Escapes that were sent; one that could not be sent is not counted.
    public var escapes: Int
    public var overlayRemaining: Bool
    public var milliseconds: Double
    /// Why an Escape could not be sent. The caller reports it and quits anyway.
    public var failure: (any Error)?

    public var metadata: [String: String] {
      [
        "quit-overlays-dismissed": String(escapes),
        "quit-overlay-remaining": String(overlayRemaining),
        "quit-dismiss-ms": String(milliseconds),
      ]
    }
  }

  /// `isOverlayOpen` and `dismiss` touch the app, so the caller must have checked that it is alive
  /// and responsive.
  public static func run(
    clock: some ResolutionClock, maximumEscapes: Int = QuitPreparation.maximumEscapes,
    settleSeconds: TimeInterval = QuitPreparation.settleSeconds,
    pollInterval: TimeInterval = QuitPreparation.pollInterval,
    isOverlayOpen: () -> Bool, dismiss: () throws -> Void
  ) -> Outcome {
    precondition(settleSeconds > 0 && pollInterval > 0)
    let start = clock.now
    func outcome(escapes: Int, remaining: Bool, failure: (any Error)? = nil) -> Outcome {
      Outcome(
        escapes: escapes, overlayRemaining: remaining,
        milliseconds: (clock.now - start) * 1000, failure: failure)
    }
    var escapes = 0
    var open = isOverlayOpen()
    while open && escapes < maximumEscapes {
      do {
        try dismiss()
      } catch {
        return outcome(escapes: escapes, remaining: true, failure: error)
      }
      escapes += 1
      let deadline = clock.now + settleSeconds
      repeat {
        clock.sleep(min(pollInterval, deadline - clock.now))
        open = isOverlayOpen()
      } while open && clock.now < deadline
    }
    return outcome(escapes: escapes, remaining: open)
  }
}
