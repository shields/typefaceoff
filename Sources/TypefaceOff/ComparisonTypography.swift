import SwiftUI
import TypefaceCore

struct ComparisonTypography: View {
  @ObservedObject var model: WorkbenchModel
  @ObservedObject var state: ComparisonInspectorState
  @Environment(\.workbenchUndoManager) private var undoManager

  private var comparison: Comparison { model.comparison }
  private var rows: [PairedFontFeature] {
    PairedFontFeature.rows(
      a: installed(.a)?.face.features ?? [], b: installed(.b)?.face.features ?? [])
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 0) {
        Text("Typography").fontWeight(.semibold)
        if rows.contains(where: changed) {
          Button("Reset") {
            model.edit("Reset typography", undoManager: undoManager) {
              for side in [Side.a, .b] where installed(side) != nil { $0[side]?.features = [:] }
            }
          }.buttonStyle(.bordered).controlSize(.small).padding(.leading, 8)
            .accessibilityIdentifier("Reset typography section")
        }
        Spacer(minLength: 0)
        letter(.a).frame(width: 24)
        letter(.b).frame(width: 24)
        Color.clear.frame(width: 20, height: 1)
      }.frame(height: 24)
      ForEach(FontFeature.Group.allCases, id: \.self) { group in
        let features = rows.filter { $0.feature.group == group }
        if !features.isEmpty {
          DisclosureGroup(
            isExpanded: Binding(
              get: { !state.collapsedGroups.contains(group) },
              set: { expanded in
                if expanded {
                  state.collapsedGroups.remove(group)
                } else {
                  state.collapsedGroups.insert(group)
                }
              })
          ) {
            VStack(alignment: .leading, spacing: 2) {
              ForEach(features) { row in featureRow(row) }
            }.padding(.top, 4)
          } label: {
            Text(verbatim: group.rawValue).font(.system(size: 11))
              .foregroundStyle(WorkbenchStyle.secondaryInk)
          }
        }
      }
    }.buttonStyle(.borderless)
  }

  private func featureRow(_ row: PairedFontFeature) -> some View {
    let selected = state.selectedFeature == row.id
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Button {
          state.selectedFeature = row.id
        } label: {
          Text(verbatim: row.feature.name).fontWeight(selected ? .semibold : .regular).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("Select typography \(row.id)")
          .overlay(alignment: .leading) {
            if selected { Rectangle().frame(width: 2, height: 16).offset(x: -12) }
          }
        if row.id.hasPrefix("ot.") {
          Text(verbatim: String(row.id.dropFirst(3))).font(.system(size: 11, design: .monospaced))
            .foregroundStyle(WorkbenchStyle.secondaryInk).padding(.horizontal, 8)
        }
        ForEach([Side.a, .b], id: \.self) { side in
          Group {
            if let feature = row[side] {
              if feature.isAutomatic {
                Text("Auto").font(.system(size: 9)).foregroundStyle(WorkbenchStyle.secondaryInk)
              } else if binary(feature) {
                InspectorFeatureToggle(
                  label: "\(side.fontName) \(feature.name)",
                  identifier: "\(side.fontName) feature \(feature.id)",
                  isOn: value(feature, side: side) == feature.options[1].value
                ) { choose(feature, value: feature.options[$0 ? 1 : 0].value, side: side) }
              } else {
                Color.clear.frame(height: 1)
              }
            } else {
              Text("—").foregroundStyle(WorkbenchStyle.secondaryInk)
            }
          }.frame(width: 24)
        }
        Group {
          if changed(row) {
            ResetButton(label: "Reset \(row.feature.name)") {
              model.edit("Reset typography", undoManager: undoManager) {
                for side in [Side.a, .b] where row[side] != nil {
                  $0[side]?.features.removeValue(forKey: row.id)
                }
              }
            }.accessibilityIdentifier("Reset feature \(row.id)")
          } else {
            Color.clear.frame(height: 1)
          }
        }.frame(width: 20)
      }.frame(minHeight: 22)
      ForEach([Side.a, .b], id: \.self) { side in
        if let feature = row[side], !feature.isAutomatic && !binary(feature) {
          HStack(spacing: 8) {
            letter(side).frame(width: 24)
            InspectorFeaturePicker(
              feature: feature, value: value(feature, side: side),
              identifier: "\(side.fontName) feature \(feature.id)"
            ) { choose(feature, value: $0, side: side) }.fixedSize()
          }.frame(minHeight: 24)
        }
      }
      if !row.feature.isAutomatic,
        selected || row.differs(a: comparison.a.features, b: comparison.b?.features ?? [:])
      {
        HStack(spacing: 8) {
          ForEach([Side.a, .b], id: \.self) { side in
            if let feature = row[side], let config = installed(side) {
              InspectorFeaturePreview(feature: feature, config: config, side: side)
                .frame(maxWidth: .infinity)
            } else {
              Color.clear.frame(maxWidth: .infinity, minHeight: 22)
            }
          }
        }
      }
    }
  }

  private func binary(_ feature: FontFeature) -> Bool {
    feature.options.count == 2 && feature.options.map(\.name) == ["Off", "On"]
  }

  private func value(_ feature: FontFeature, side: Side) -> Int {
    comparison[side]?.features[feature.id] ?? feature.defaultValue
  }

  private func choose(_ feature: FontFeature, value: Int, side: Side) {
    state.selectedFeature = feature.id
    model.edit("Change typography", undoManager: undoManager) {
      $0.setFeature(feature, value: value, side: side)
    }
  }

  private func changed(_ row: PairedFontFeature) -> Bool {
    row.isChanged(a: comparison.a.features, b: comparison.b?.features ?? [:])
  }

  private func installed(_ side: Side) -> FontConfiguration? {
    comparison[side].flatMap { FontRenderer.isAvailable($0) ? $0 : nil }
  }

  private func letter(_ side: Side) -> some View {
    Text(side == .a ? "A" : "B").fontWeight(.semibold)
      .foregroundStyle(Color(nsColor: side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue))
  }
}

private struct InspectorFeaturePicker: NSViewRepresentable {
  let feature: FontFeature
  let value: Int
  let identifier: String
  let change: (Int) -> Void
  @Environment(\.isEnabled) private var enabled

  func makeCoordinator() -> Coordinator { Coordinator(change: change) }

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: false)
    button.isBordered = false
    button.controlSize = .small
    button.font = .systemFont(ofSize: 13)
    button.target = context.coordinator
    button.action = #selector(Coordinator.choose(_:))
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.change = change
    button.removeAllItems()
    for option in feature.options {
      let item = NSMenuItem(title: option.name, action: nil, keyEquivalent: "")
      item.tag = option.value
      button.menu!.addItem(item)
    }
    button.selectItem(withTag: value)
    button.isEnabled = enabled
    button.setAccessibilityLabel(feature.name)
    button.setAccessibilityIdentifier(identifier)
  }

  @MainActor final class Coordinator: NSObject {
    var change: (Int) -> Void
    init(change: @escaping (Int) -> Void) { self.change = change }
    @objc func choose(_ sender: NSPopUpButton) { change(sender.selectedItem!.tag) }
  }
}

private struct InspectorFeatureToggle: NSViewRepresentable {
  let label: String
  let identifier: String
  let isOn: Bool
  let change: (Bool) -> Void
  @Environment(\.isEnabled) private var enabled

  func makeCoordinator() -> Coordinator { Coordinator(change: change) }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.toggle(_:)))
    button.controlSize = .small
    button.contentTintColor = NSColor(WorkbenchStyle.ink)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.change = change
    button.state = isOn ? .on : .off
    button.isEnabled = enabled
    button.setAccessibilityLabel(label)
    button.setAccessibilityIdentifier(identifier)
  }

  @MainActor final class Coordinator: NSObject {
    var change: (Bool) -> Void
    init(change: @escaping (Bool) -> Void) { self.change = change }
    @objc func toggle(_ sender: NSButton) { change(sender.state == .on) }
  }
}

struct InspectorFeaturePreview: View {
  let feature: FontFeature
  let config: FontConfiguration
  let side: Side
  @State private var preview: FontFeaturePreview?
  @State private var loaded = false

  private var previewConfig: FontConfiguration {
    var result = config
    result.size = 17
    result.leading = nil
    return result
  }

  var body: some View {
    HStack(spacing: 5) {
      Text(side == .a ? "A" : "B").font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color(nsColor: side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue))
      if let preview {
        FontPreviewText(config: preview.before, text: preview.text, size: 17)
        Text("→").font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
        FontPreviewText(config: preview.after, text: preview.text, size: 17)
      } else if loaded {
        Text("No preview available").font(.system(size: 10)).foregroundStyle(
          WorkbenchStyle.secondaryInk
        )
        .accessibilityIdentifier("\(side.fontName) no preview for \(feature.id)")
      } else {
        Color.clear
      }
    }.frame(height: 22)
      .task(id: previewConfig) {
        let work = FuzzDiagnostics.shared.beginWork("feature-preview")
        defer {
          FuzzDiagnostics.shared.endWork(
            work, kind: "feature-preview", outcome: Task.isCancelled ? "cancelled" : "completed")
        }
        loaded = false
        preview = nil
        do {
          let result = try await FontFeaturePreviewEngine.shared.preview(
            feature: feature, config: previewConfig)
          try Task.checkCancellation()
          preview = result
          loaded = true
        } catch {}
      }
  }
}
