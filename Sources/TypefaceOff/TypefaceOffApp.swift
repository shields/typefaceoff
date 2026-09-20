import SwiftUI

@main
struct TypefaceOffApp: App {
  var body: some Scene {
    WindowGroup("Typeface/Off") {
      WorkbenchWindow()
    }
    .restorationBehavior(.disabled)
    .defaultSize(width: 1440, height: 900)
    .commands { WorkbenchCommands() }
  }
}

struct WorkbenchWindow: View {
  @StateObject private var model = WorkbenchModel()
  @State private var undoManager: UndoManager?

  var body: some View {
    Group {
      // Install the window's Undo history before controls capture their actions.
      if let undoManager {
        WorkbenchView(model: model)
          .environment(\.workbenchUndoManager, undoManager)
      }
    }
    .frame(minWidth: 1080, minHeight: 680)
    .background(WindowUndoManager(undoManager: $undoManager))
    .preferredColorScheme(.dark)
  }
}
