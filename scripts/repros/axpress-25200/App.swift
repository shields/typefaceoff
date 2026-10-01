import AppKit
import SwiftUI

struct SheetText: NSViewRepresentable {
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
    text.isEditable = false
    text.string = "Sample"
    if !CommandLine.arguments.contains("--without-setter") {
      if CommandLine.arguments.contains("--identifier") {
        text.setAccessibilityIdentifier("Specimen")
      } else {
        text.setAccessibilityLabel("Specimen")
      }
    }
    scroll.documentView = text
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {}
}

@main
struct AXPressRepro: App {
  @State private var showSheet = false

  var body: some Scene {
    Window("AXPress repro", id: "repro") {
      Button("Open sheet") { showSheet = true }
        .padding().frame(width: 320, height: 180)
        .sheet(isPresented: $showSheet) {
          VStack {
            SheetText().frame(width: 240, height: 80)
            Button("Cancel") { showSheet = false }
          }.padding()
        }
    }.restorationBehavior(.disabled)
  }
}
