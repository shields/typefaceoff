import Foundation

/// AppKit drops a quit request that arrives while a sheet is open, and an open menu delays it, so
/// the driver closes what a run leaves open before it asks the app to quit.
public enum QuitPreparation {
  public static let maximumEscapes = 3
  /// The longest wait for what is open to change after an Escape. A sheet needs a moment to close,
  /// and a quit sent before it has gone is dropped; `Overlay.isChanged` says what ends the wait
  /// early.
  public static let settleSeconds: TimeInterval = 0.5
  public static let pollInterval: TimeInterval = 0.05

  /// The layer that receives input, as discovery sees it: a menu over a sheet is the menu.
  public enum Overlay: Equatable, Sendable {
    case located(role: String?, depth: Int)
    /// An overlay has focus but nothing locates it.
    case unlocated

    /// Nil when nothing modal is open and no overlay is unaccounted for.
    public init?(_ modal: ModalSelection) {
      if let root = modal.root {
        self = .located(role: modal.rootRole, depth: root.count)
      } else if modal.unlocated {
        self = .unlocated
      } else {
        return nil
      }
    }

    /// Whether `observation`, taken after an Escape, shows that this layer closed or gave way to
    /// another. A replacement with the same role and depth looks the same, and so does any
    /// observation or layer that is unlocated, which may be this layer with a failed read. Those
    /// count as no change, so the loop waits out its window: an Escape sent on a false change could
    /// land on the workbench.
    func isChanged(by observation: Overlay?) -> Bool {
      guard let observation else { return true }
      guard case .located(let role, let depth) = self,
        case .located(let observedRole, let observedDepth) = observation
      else { return false }
      return role != observedRole || depth != observedDepth
    }
  }

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

  /// `openOverlay` and `dismiss` touch the app, so the caller must have checked that it is alive
  /// and responsive.
  public static func run(
    clock: some ResolutionClock, maximumEscapes: Int = QuitPreparation.maximumEscapes,
    settleSeconds: TimeInterval = QuitPreparation.settleSeconds,
    pollInterval: TimeInterval = QuitPreparation.pollInterval,
    openOverlay: () -> Overlay?, dismiss: () throws -> Void
  ) -> Outcome {
    precondition(settleSeconds > 0 && pollInterval > 0)
    let start = clock.now
    func outcome(escapes: Int, remaining: Bool, failure: (any Error)? = nil) -> Outcome {
      Outcome(
        escapes: escapes, overlayRemaining: remaining,
        milliseconds: (clock.now - start) * 1000, failure: failure)
    }
    var escapes = 0
    var open = openOverlay()
    while let layer = open, escapes < maximumEscapes {
      do {
        try dismiss()
      } catch {
        return outcome(escapes: escapes, remaining: true, failure: error)
      }
      escapes += 1
      let deadline = clock.now + settleSeconds
      repeat {
        clock.sleep(min(pollInterval, deadline - clock.now))
        open = openOverlay()
      } while !layer.isChanged(by: open) && clock.now < deadline
    }
    return outcome(escapes: escapes, remaining: open != nil)
  }
}
