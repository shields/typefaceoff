import AppKit
import SwiftUI
import TypefaceCore

struct WorkbenchModePicker: NSViewRepresentable {
  @Binding var mode: ComparisonMode
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
  }

  @MainActor final class Coordinator: NSObject {
    var mode: Binding<ComparisonMode>
    init(mode: Binding<ComparisonMode>) { self.mode = mode }

    @objc func choose(_ sender: NSSegmentedControl) {
      mode.wrappedValue = WorkbenchModePicker.modes[sender.selectedSegment]
    }
  }
}
