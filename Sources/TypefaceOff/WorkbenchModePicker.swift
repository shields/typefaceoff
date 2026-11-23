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

struct WorkbenchModePicker: NSViewRepresentable {
  @Binding var mode: ComparisonMode
  let allowsLanguages: Bool
  private static let modes: [ComparisonMode] = [.text, .glyph, .languages]

  func makeCoordinator() -> Coordinator { Coordinator(mode: $mode) }

  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl(
      labels: ["Text", "Glyph", "Languages"], trackingMode: .selectOne,
      target: context.coordinator, action: #selector(Coordinator.choose(_:)))
    control.selectedSegmentBezelColor = NSColor(WorkbenchStyle.hairline)
    control.setAccessibilityLabel("Comparison mode")
    return control
  }

  func updateNSView(_ control: NSSegmentedControl, context: Context) {
    context.coordinator.mode = $mode
    control.selectedSegment = Self.modes.firstIndex(of: mode)!
    control.setEnabled(allowsLanguages, forSegment: 2)
  }

  @MainActor final class Coordinator: NSObject {
    var mode: Binding<ComparisonMode>
    init(mode: Binding<ComparisonMode>) { self.mode = mode }

    @objc func choose(_ sender: NSSegmentedControl) {
      mode.wrappedValue = WorkbenchModePicker.modes[sender.selectedSegment]
    }
  }
}
