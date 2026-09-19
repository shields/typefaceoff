import AppKit
import Combine

/// Owned by the workbench so the reading position outlives either text view.
@MainActor final class SpecimenScrollPosition: ObservableObject {
  private var fraction = 0.0
  private var observations: [Observation] = []
  private var updating = false

  func attach(_ scroll: NSScrollView) {
    observations.removeAll { $0.scroll == nil }
    guard !observations.contains(where: { $0.scroll === scroll }) else { return }
    observations.append(Observation(scroll: scroll, owner: self))
    restore()
  }

  func detach(_ scroll: NSScrollView) {
    observations.removeAll { $0.scroll === scroll || $0.scroll == nil }
  }

  func reset() {
    fraction = 0
    restore()
  }

  func preserveDuringUpdate(_ update: () -> Void) {
    let wasUpdating = updating
    updating = true
    update()
    updating = wasUpdating
    restore()
  }

  private func scrolled(_ scroll: NSScrollView) {
    guard !updating else { return }
    let extent = Self.extent(scroll)
    // A short specimen has no reading position to impose on its longer partner.
    guard extent > 0 else { return }
    fraction = min(1, max(0, scroll.contentView.bounds.minY / extent))
    restore(except: scroll)
  }

  private func restore(except source: NSScrollView? = nil) {
    guard !updating else { return }
    updating = true
    defer { updating = false }
    for observation in observations {
      guard let scroll = observation.scroll, scroll !== source else { continue }
      let clip = scroll.contentView
      guard clip.bounds.width > 0, clip.bounds.height > 0 else { continue }
      clip.scroll(to: NSPoint(x: clip.bounds.minX, y: fraction * Self.extent(scroll)))
      scroll.reflectScrolledClipView(clip)
    }
  }

  private static func extent(_ scroll: NSScrollView) -> Double {
    max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
  }

  @MainActor private final class Observation: NSObject {
    weak var scroll: NSScrollView?
    weak var owner: SpecimenScrollPosition?
    var viewportSize: NSSize

    init(scroll: NSScrollView, owner: SpecimenScrollPosition) {
      self.scroll = scroll
      self.owner = owner
      viewportSize = scroll.contentView.bounds.size
      super.init()
      scroll.contentView.postsBoundsChangedNotifications = true
      scroll.contentView.postsFrameChangedNotifications = true
      scroll.documentView?.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(
        self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification,
        object: scroll.contentView)
      NotificationCenter.default.addObserver(
        self, selector: #selector(viewportResized), name: NSView.frameDidChangeNotification,
        object: scroll.contentView)
      NotificationCenter.default.addObserver(
        self, selector: #selector(documentResized), name: NSView.frameDidChangeNotification,
        object: scroll.documentView)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func boundsChanged(_ notification: Notification) {
      guard let scroll else { return }
      let size = scroll.contentView.bounds.size
      if viewportSize != size {
        viewportSize = size
        owner?.restore()
      } else {
        owner?.scrolled(scroll)
      }
    }

    @objc private func documentResized(_ notification: Notification) {
      owner?.restore()
    }

    @objc private func viewportResized(_ notification: Notification) {
      guard let scroll else { return }
      viewportSize = scroll.contentView.bounds.size
      owner?.restore()
    }
  }
}
