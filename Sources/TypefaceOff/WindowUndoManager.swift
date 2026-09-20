import SwiftUI

private struct WorkbenchUndoManagerKey: EnvironmentKey {
  static var defaultValue: UndoManager? { nil }
}

extension EnvironmentValues {
  var workbenchUndoManager: UndoManager? {
    get { self[WorkbenchUndoManagerKey.self] ?? undoManager }
    set { self[WorkbenchUndoManagerKey.self] = newValue }
  }
}

/// WindowGroup does not supply SwiftUI's document Undo manager. Share the native
/// window's manager so controls and the standard Edit menu use the same history.
struct WindowUndoManager: NSViewRepresentable {
  @Binding var undoManager: UndoManager?

  func makeNSView(context: Context) -> Bridge {
    let view = Bridge()
    view.manager = $undoManager
    return view
  }

  func updateNSView(_ nsView: Bridge, context: Context) {}

  final class Bridge: NSView {
    var manager: Binding<UndoManager?> = .constant(nil)

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let undoManager = window?.undoManager else { return }
      // Publish after SwiftUI finishes attaching the view to its window.
      Task { @MainActor [manager] in
        manager.wrappedValue = undoManager
      }
    }
  }
}
