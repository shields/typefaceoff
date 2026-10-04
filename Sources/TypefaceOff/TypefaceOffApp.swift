import AppKit
import SwiftUI

@main
struct TypefaceOffApp: App {
  @NSApplicationDelegateAdaptor(TypefaceOffAppDelegate.self) private var appDelegate

  init() {
    #if TYPEFACEOFF_STARTUP_BENCHMARK
      StartupDiagnostics.mark("appInit")
    #endif
    if ProcessInfo.processInfo.environment["TYPEFACEOFF_TESTING"] == "1" {
      // App-hosted tests need AppKit and SwiftUI, but must not activate on the desktop.
      precondition(NSApplication.shared.setActivationPolicy(.prohibited))
    }
    // Font discovery can overlap AppKit's launch work instead of delaying the first window.
    DispatchQueue.global(qos: .userInitiated).async { _ = WorkbenchModel.installedCatalog }
  }

  var body: some Scene {
    WindowGroup("Typeface/Off") {
      WorkbenchWindow()
    }
    .restorationBehavior(.disabled)
    .defaultSize(width: 1440, height: 900)
    .commands { WorkbenchCommands() }
  }
}

@MainActor
final class TypefaceOffAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Publish the compiled image explicitly to avoid a blank Dock/app-switcher icon.
    NSApp.applicationIconImage = NSImage(named: "AppIcon")!
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
