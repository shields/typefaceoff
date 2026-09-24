import SwiftUI
import TypefaceCore

/// Each window supplies its own bindings and actions to the menu bar.
@MainActor struct WorkbenchActions {
  let showA: Binding<Bool>
  let showB: Binding<Bool>
  let mode: Binding<ComparisonMode>
  let shape: Binding<Bool>
  let spacing: Binding<Bool>
  let frequency: Binding<Bool>
  let canMatch: Bool
  let canSwap: Bool
  let match: () -> Void
  let swap: () -> Void
  let editText: () -> Void

  init(
    model: WorkbenchModel, undoManager: UndoManager?, showA: Binding<Bool>,
    showB: Binding<Bool>, mode: Binding<ComparisonMode>, shape: Binding<Bool>,
    spacing: Binding<Bool>, frequency: Binding<Bool>, match: @escaping () -> Void,
    editText: @escaping () -> Void
  ) {
    self.showA = showA
    self.showB = showB
    self.mode = mode
    self.shape = shape
    self.spacing = spacing
    self.frequency = frequency
    canMatch =
      FontRenderer.isAvailable(model.comparison.a)
      && model.comparison.b.map { FontRenderer.isAvailable($0) } == true
    canSwap = model.comparison.b != nil
    self.match = match
    swap = { model.edit("Swap fonts", undoManager: undoManager) { $0.swap() } }
    self.editText = editText
  }
}

private struct WorkbenchActionsKey: FocusedValueKey {
  typealias Value = WorkbenchActions
}

extension FocusedValues {
  var workbenchActions: WorkbenchActions? {
    get { self[WorkbenchActionsKey.self] }
    set { self[WorkbenchActionsKey.self] = newValue }
  }
}

struct WorkbenchCommands: Commands {
  @FocusedValue(\.workbenchActions) private var actions

  var body: some Commands {
    CommandGroup(replacing: .sidebar) {
      WorkbenchMenuItems(section: .inspectors, actions: actions)
    }
    CommandGroup(after: .toolbar) {
      WorkbenchMenuItems(section: .view, actions: actions)
    }
    CommandMenu("Comparison") {
      WorkbenchMenuItems(section: .comparison, actions: actions)
    }
  }
}

struct WorkbenchMenuItems: View {
  enum Section { case inspectors, view, comparison }
  let section: Section
  let actions: WorkbenchActions?

  var body: some View {
    Group {
      switch section {
      case .inspectors:
        Toggle("Font A inspector", isOn: actions?.showA ?? .constant(false))
          .keyboardShortcut("1", modifiers: [.command, .option])
        Toggle("Font B inspector", isOn: actions?.showB ?? .constant(false))
          .keyboardShortcut("2", modifiers: [.command, .option])
      case .view:
        Toggle("Text view", isOn: mode(.text)).keyboardShortcut("1")
        Toggle("Glyph view", isOn: mode(.glyph)).keyboardShortcut("2")
        Divider()
        Toggle("Highlight shape differences", isOn: actions?.shape ?? .constant(false))
          .keyboardShortcut("1", modifiers: [.command, .shift])
        Toggle("Highlight spacing differences", isOn: actions?.spacing ?? .constant(false))
          .keyboardShortcut("2", modifiers: [.command, .shift])
        Toggle("Weight by character frequency", isOn: actions?.frequency ?? .constant(false))
          .keyboardShortcut("f", modifiers: [.command, .shift])
      case .comparison:
        Button("Match fonts…") { actions?.match() }
          .keyboardShortcut("m", modifiers: [.command, .shift])
          .disabled(actions?.canMatch != true)
        Button("Swap fonts") { actions?.swap() }
          .keyboardShortcut("s", modifiers: [.command, .option])
          .disabled(actions?.canSwap != true)
        Divider()
        Button("Edit sample text…") { actions?.editText() }
          .keyboardShortcut("e", modifiers: [.command, .shift])
      }
    }.disabled(actions == nil)
  }

  private func mode(_ value: ComparisonMode) -> Binding<Bool> {
    Binding(
      get: { actions?.mode.wrappedValue == value },
      set: { _ in actions?.mode.wrappedValue = value })
  }
}
