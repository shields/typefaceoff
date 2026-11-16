import AppKit
import SwiftUI

struct DifferenceStrip<Content: View>: NSViewRepresentable {
  let count: Int
  let selection: Int?
  let navigate: (Int) -> Void
  @ViewBuilder let content: () -> Content

  func makeNSView(context: Context) -> DifferenceStripView {
    let view = DifferenceStripView()
    view.documentView = NSHostingView(
      rootView: InheritedContent(content: content(), values: context.environment))
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ view: DifferenceStripView, context: Context) {
    let document = view.documentView as! NSHostingView<InheritedContent>
    document.rootView = InheritedContent(content: content(), values: context.environment)
    document.setFrameSize(NSSize(width: count * 48, height: 76))
    view.navigate = navigate
    view.follow(selection)
  }

  private struct InheritedContent: View {
    let content: Content
    let values: EnvironmentValues

    var body: some View { content.environment(\.self, values) }
  }
}

final class DifferenceStripView: NSScrollView {
  var navigate: (Int) -> Void = { _ in }
  private var selection: Int?

  convenience init() {
    self.init(frame: .zero)
    drawsBackground = false
    borderType = .noBorder
    horizontalScrollElasticity = .none
    verticalScrollElasticity = .none
    setAccessibilityLabel("Differences")
    setAccessibilityIdentifier("Differences strip scroll area")
  }

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 123: navigate(-1)
    case 124: navigate(1)
    default: super.keyDown(with: event)
    }
  }

  override func scrollWheel(with event: NSEvent) {
    let delta =
      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
      ? event.scrollingDeltaX : event.scrollingDeltaY
    let proposed = contentView.bounds.offsetBy(
      dx: -delta * (event.hasPreciseScrollingDeltas ? 1 : 12), dy: 0)
    contentView.scroll(to: contentView.constrainBoundsRect(proposed).origin)
    reflectScrolledClipView(contentView)
  }

  func follow(_ index: Int?) {
    guard selection != index else { return }
    selection = index
    revealSelection()
  }

  override func tile() {
    super.tile()
    revealSelection()
  }

  private func revealSelection() {
    if let selection {
      documentView?.scrollToVisible(NSRect(x: selection * 48, y: 0, width: 48, height: 76))
    }
  }
}
