import SwiftUI
import TypefaceCore

/// Retain disclosure and scroll state while the inspector is collapsed.
struct InspectorPanel: View {
  let document: WorkbenchDocument
  let side: Side
  let isVisible: Bool

  var body: some View {
    FontInspector(document: document, side: side)
      .frame(width: 246)
      .frame(width: isVisible ? 246 : 0)
      .clipped()
      .disabled(!isVisible)
      .allowsHitTesting(isVisible)
      .accessibilityHidden(!isVisible)
  }
}
