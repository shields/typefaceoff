import SwiftUI
import TypefaceCore

@MainActor struct WorkbenchActions {
  let inspector: Binding<Bool>
  let mode: Binding<ComparisonMode>
  let shape: Binding<Bool>
  let spacing: Binding<Bool>
  let frequency: Binding<Bool>
  let zoom: Binding<Double>
  let linked: Binding<Bool>
  let canMatch: Bool
  let canSwap: Bool
  let canResetAppearance: Bool
  let canResetTypography: Bool
  let find: () -> Void
  let focusFont: (Side) -> Void
  let navigate: (Int) -> Void
  let match: () -> Void
  let swap: () -> Void
  let equalizeSizes: () -> Void
  let resetAppearance: () -> Void
  let resetTypography: () -> Void
  let editText: () -> Void

  init(
    model: WorkbenchModel, undoManager: UndoManager?, inspector: Binding<Bool>,
    mode: Binding<ComparisonMode>, shape: Binding<Bool>, spacing: Binding<Bool>,
    frequency: Binding<Bool>, zoom: Binding<Double>, find: @escaping () -> Void,
    focusFont: @escaping (Side) -> Void, navigate: @escaping (Int) -> Void,
    match: @escaping () -> Void, editText: @escaping () -> Void
  ) {
    self.inspector = inspector
    self.mode = mode
    self.shape = shape
    self.spacing = spacing
    self.frequency = frequency
    self.zoom = zoom
    self.find = find
    self.focusFont = focusFont
    self.navigate = navigate
    canMatch =
      FontRenderer.isAvailable(model.comparison.a)
      && model.comparison.b.map { FontRenderer.isAvailable($0) } == true
    canSwap = model.comparison.b != nil
    canResetAppearance = model.comparison.hasAppearanceChanges(catalog: model.catalog)
    canResetTypography = [model.comparison.a, model.comparison.b].compactMap { $0 }.contains {
      config in
      FontRenderer.isAvailable(config)
        && config.face.features.contains {
          (config.features[$0.id] ?? $0.defaultValue) != $0.defaultValue
        }
    }
    linked = Binding(
      get: { model.comparison.appearanceLocked },
      set: { value in
        model.edit("Link appearance", undoManager: undoManager) {
          $0.appearanceLocked = value
          $0.calibrate()
        }
      })
    self.match = match
    swap = { model.edit("Swap fonts", undoManager: undoManager) { $0.swap() } }
    equalizeSizes = {
      model.edit("Make sizes equal", undoManager: undoManager) {
        SpecificationSetting.size.apply(
          .number($0.a.size), to: &$0, side: .a, both: true, catalog: model.catalog)
      }
    }
    resetAppearance = {
      model.edit("Reset appearance", undoManager: undoManager) {
        $0.resetAppearance(catalog: model.catalog)
      }
    }
    resetTypography = {
      model.edit("Reset typography", undoManager: undoManager) {
        for side in [Side.a, .b] {
          if let config = $0[side], FontRenderer.isAvailable(config) { $0[side]?.features = [:] }
        }
      }
    }
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
    CommandGroup(after: .pasteboard) {
      WorkbenchMenuItems(section: .find, actions: actions)
    }
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
  enum Section { case find, inspectors, view, comparison }
  let section: Section
  let actions: WorkbenchActions?

  var body: some View {
    Group {
      switch section {
      case .find:
        Button(actions?.mode.wrappedValue == .languages ? "Search Languages" : "Find Character") {
          actions?.find()
        }
        .keyboardShortcut("f")
      case .inspectors:
        Toggle("Show Inspector", isOn: actions?.inspector ?? .constant(false))
          .keyboardShortcut("i", modifiers: [.command, .control])
      case .view:
        Toggle("Text", isOn: mode(.text)).keyboardShortcut("1")
        Toggle("Glyph", isOn: mode(.glyph)).keyboardShortcut("2")
        Toggle("Languages", isOn: mode(.languages)).keyboardShortcut("3")
        Divider()
        Toggle("Shape", isOn: actions?.shape ?? .constant(false))
          .keyboardShortcut("1", modifiers: [.command, .shift])
        Toggle("Spacing", isOn: actions?.spacing ?? .constant(false))
          .keyboardShortcut("2", modifiers: [.command, .shift])
        Toggle("Frequency", isOn: actions?.frequency ?? .constant(false))
          .keyboardShortcut("f", modifiers: [.command, .shift])
        Divider()
        Button("Zoom In") {
          if let actions { actions.zoom.wrappedValue = min(8, actions.zoom.wrappedValue * 1.25) }
        }
        .keyboardShortcut("+").disabled(
          actions?.mode.wrappedValue != .glyph || actions?.zoom.wrappedValue == 8)
        Button("Zoom Out") {
          if let actions { actions.zoom.wrappedValue = max(1, actions.zoom.wrappedValue / 1.25) }
        }
        .keyboardShortcut("-").disabled(
          actions?.mode.wrappedValue != .glyph || actions?.zoom.wrappedValue == 1)
        Button("Actual Size") { actions?.zoom.wrappedValue = 1 }
          .keyboardShortcut("0").disabled(actions?.mode.wrappedValue != .glyph)
        Button("Previous Character") { actions?.navigate(-1) }
        Button("Next Character") { actions?.navigate(1) }
      case .comparison:
        Button("Font A") { actions?.focusFont(.a) }
          .keyboardShortcut("1", modifiers: [.command, .option])
        Button("Font B") { actions?.focusFont(.b) }
          .keyboardShortcut("2", modifiers: [.command, .option])
        Button("Swap Fonts") { actions?.swap() }
          .keyboardShortcut("s", modifiers: [.command, .option]).disabled(actions?.canSwap != true)
        Toggle("Link Appearance", isOn: actions?.linked ?? .constant(false)).disabled(
          actions?.canMatch != true)
        Button("Make Sizes Equal") { actions?.equalizeSizes() }.disabled(actions?.canMatch != true)
        Button("Reset Appearance") { actions?.resetAppearance() }.disabled(
          actions?.canResetAppearance != true)
        Button("Reset Typography") { actions?.resetTypography() }.disabled(
          actions?.canResetTypography != true)
        Divider()
        Button("Match…") { actions?.match() }
          .keyboardShortcut("m", modifiers: [.command, .shift]).disabled(actions?.canMatch != true)
        Button("Edit Sample Text…") { actions?.editText() }
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
