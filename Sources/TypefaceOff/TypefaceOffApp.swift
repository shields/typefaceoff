import SwiftUI
import TypefaceCore
import UniformTypeIdentifiers

extension UTType {
  static let typefaceComparison = UTType(
    exportedAs: "com.shields.typefaceoff.comparison", conformingTo: .json)
}

@main
struct TypefaceOffApp: App {
  var body: some Scene {
    DocumentGroup(newDocument: { WorkbenchDocument() }) { file in
      WorkbenchView(document: file.document)
        .frame(minWidth: 1080, minHeight: 680)
        .preferredColorScheme(.dark)
    }
    .defaultSize(width: 1440, height: 900)
    .commands { SidebarCommands() }
  }
}
