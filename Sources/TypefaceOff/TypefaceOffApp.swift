import SwiftUI
import TypefaceCore
import UniformTypeIdentifiers

extension UTType {
  static let typefaceComparison = UTType(
    exportedAs: "com.shields.typefaceoff.comparison", conformingTo: .json)
}

@main
struct TypefaceOffApp: App {
  @NSApplicationDelegateAdaptor(WorkbenchAppDelegate.self) private var appDelegate

  var body: some Scene {
    DocumentGroup(newDocument: { WorkbenchDocument() }) { file in
      WorkbenchView(document: file.document)
        .frame(minWidth: 1080, minHeight: 680)
        .preferredColorScheme(.dark)
    }
    .defaultLaunchBehavior(.suppressed)
    .defaultSize(width: 1440, height: 900)
    .commands { WorkbenchCommands() }
  }
}

@MainActor
final class WorkbenchAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // File-opening and restoration launches already have a document on the way.
    if notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true {
      openComparisonIfNeeded()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag { openComparisonIfNeeded() }
    return true
  }

  func openComparisonIfNeeded() {
    let controller = NSDocumentController.shared
    if controller.documents.isEmpty {
      controller.newDocument(nil)
    }
  }
}
