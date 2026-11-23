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
