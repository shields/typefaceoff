import AppKit
import SwiftUI

struct FontFamilyPicker: View {
  let families: [String]
  let currentFamily: String?
  let allowsNone: Bool
  let choose: (String?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var selection: Choice?

  private enum Choice: Hashable {
    case none
    case family(String)

    var title: String {
      switch self {
      case .none: "None"
      case .family(let name): name
      }
    }

    var family: String? {
      switch self {
      case .none: nil
      case .family(let name): name
      }
    }
  }

  private var choices: [Choice] {
    ((allowsNone ? [Choice.none] : []) + families.map(Choice.family)).filter {
      query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    VStack(spacing: 10) {
      FontSearchField(
        text: $query, move: move, submit: confirm, cancel: { dismiss() }
      ).padding([.top, .horizontal])
      ScrollViewReader { proxy in
        if choices.isEmpty {
          Text("No matching fonts").foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(choices, id: \.self, selection: $selection) { choice in
            Button {
              choose(choice.family)
            } label: {
              Text(verbatim: choice.title).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).tag(choice).id(choice)
          }
          .onKeyPress(.return) {
            confirm()
            return .handled
          }
          .onChange(of: selection) { _, choice in
            if let choice { proxy.scrollTo(choice) }
          }
        }
      }
    }
    .frame(width: 300, height: 400)
    .onAppear {
      let current = currentFamily.map(Choice.family) ?? .none
      selection = choices.contains(current) ? current : choices.first
    }
    .onChange(of: query) {
      if !choices.contains(where: { $0 == selection }) { selection = choices.first }
    }
    .onExitCommand { dismiss() }
  }

  private func move(_ offset: Int) {
    let choices = choices
    guard !choices.isEmpty else { return }
    let index =
      selection.flatMap { choices.firstIndex(of: $0) } ?? (offset > 0 ? -1 : choices.count)
    selection = choices[min(max(index + offset, 0), choices.count - 1)]
  }

  private func confirm() {
    guard let selection, choices.contains(selection) else { return }
    choose(selection.family)
  }
}

/// Keep editing the query while arrow keys move through the list's selection.
struct FontSearchField: NSViewRepresentable {
  @Binding var text: String
  var move: (Int) -> Void
  var submit: () -> Void
  var cancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSSearchField {
    let field = InitiallyFocusedSearchField()
    field.placeholderString = "Search installed fonts"
    field.setAccessibilityLabel("Search installed fonts")
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text { field.stringValue = text }
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: FontSearchField
    init(_ parent: FontSearchField) { self.parent = parent }

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
    window?.makeFirstResponder(self)
  }
}
