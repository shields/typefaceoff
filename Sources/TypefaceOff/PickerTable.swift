import AppKit

final class PickerTableView: NSTableView {
  var confirm: (() -> Void)?
  var cancel: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36: confirm!()
    case 53: cancel!()
    default: super.keyDown(with: event)
    }
  }
}

final class PickerSelectionRow: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
  }
}
