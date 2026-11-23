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
