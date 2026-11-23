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
