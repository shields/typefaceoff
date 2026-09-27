import AppKit
import SwiftUI

/// Keep editing the query while arrow keys move through the list's selection.
struct PickerSearchField: NSViewRepresentable {
  let label: String
  @Binding var text: String
  var move: (Int) -> Void
  var submit: () -> Void
  var cancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSSearchField {
    let field = InitiallyFocusedSearchField()
    field.placeholderString = label
    field.setAccessibilityLabel(label)
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.parent = self
    field.placeholderString = label
    field.setAccessibilityLabel(label)
    if field.stringValue != text { field.stringValue = text }
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: PickerSearchField
    init(_ parent: PickerSearchField) { self.parent = parent }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      parent.text = field.stringValue
    }

    func control(
      _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
      // Let the input method finish composing before handling navigation or confirmation.
      guard !textView.hasMarkedText() else { return false }
      switch commandSelector {
      case #selector(NSResponder.moveUp(_:)): parent.move(-1)
      case #selector(NSResponder.moveDown(_:)): parent.move(1)
      case #selector(NSResponder.insertNewline(_:)): parent.submit()
      case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
      default: return false
      }
      return true
    }
  }
}

private final class InitiallyFocusedSearchField: NSSearchField {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }
    // Editing that begins before the window is onscreen leaves the placeholder
    // drawn behind the typed text.
    if window.isVisible {
      window.makeFirstResponder(self)
    } else {
      window.initialFirstResponder = self
    }
  }
}
