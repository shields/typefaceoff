import AppKit
import SwiftUI
import TypefaceCore

extension Side {
  /// Prefix of every per-inspector accessibility name, such as `Font A Size`.
  var fontName: String { "Font \(rawValue.uppercased())" }
}

/// Names the `NSScrollView` that contains it. An AppKit setter cannot propagate to descendants
/// the way a SwiftUI container identifier can, which would rename every control inside.
final class ScrollAreaAnchorView: NSView {
  var name = "" { didSet { apply() } }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    apply()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    apply()
  }

  private func apply() {
    enclosingScrollView?.setAccessibilityIdentifier(name)
  }
}

struct ScrollAreaAnchor: NSViewRepresentable {
  let name: String

  func makeNSView(context: Context) -> ScrollAreaAnchorView { ScrollAreaAnchorView() }

  func updateNSView(_ view: ScrollAreaAnchorView, context: Context) { view.name = name }
}

extension View {
  /// Place inside a `ScrollView`'s content so the anchor's enclosing scroll view is that one.
  func scrollAreaIdentifier(_ name: String) -> some View {
    background(ScrollAreaAnchor(name: name).accessibilityHidden(true))
  }
}
