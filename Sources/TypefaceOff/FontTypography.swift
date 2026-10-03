import SwiftUI
import TypefaceCore

/// Preview results invalidate only the typography controls, keeping the inspector's
/// appearance controls and font picker out of those updates.
struct FontTypography: View {
  let model: WorkbenchModel
  let side: Side
  let config: FontConfiguration
  @Binding var collapsedGroups: Set<FontFeature.Group>
  @Environment(\.workbenchUndoManager) private var undoManager
  @StateObject private var previews: FeaturePreviewModel

  init(
    model: WorkbenchModel, side: Side, config: FontConfiguration,
    collapsedGroups: Binding<Set<FontFeature.Group>>
  ) {
    self.model = model
    self.side = side
    self.config = config
    _collapsedGroups = collapsedGroups
    _previews = StateObject(
      wrappedValue: FeaturePreviewModel(preparation: model.initialWork.previews(for: side)))
  }

  private var previewConfig: FontConfiguration {
    var result = config
    result.size = 21
    result.leading = nil
    return result
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Typography").font(.headline)
        Spacer()
        Button("Reset typography", systemImage: "arrow.counterclockwise") {
          edit("Reset typography") { $0[side]?.features = [:] }
        }
        .labelStyle(.iconOnly).buttonStyle(.borderless)
        .accessibilityIdentifier("\(side.fontName) Reset typography")
        .help("Restore this font’s default typography settings")
      }
      ForEach(FontFeature.Group.allCases, id: \.self) { group in
        let features = config.face.features.filter { $0.group == group }
        if !features.isEmpty {
          DisclosureGroup(
            isExpanded: Binding(
              get: { !collapsedGroups.contains(group) },
              set: { expanded in
                if expanded {
                  collapsedGroups.remove(group)
                } else {
                  collapsedGroups.insert(group)
                }
              })
          ) {
            VStack(alignment: .leading, spacing: 14) {
              ForEach(features) { feature in
                featureControl(feature, config: config)
              }
            }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
          } label: {
            Text(verbatim: group.rawValue).font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .task(id: previewConfig) { await previews.update(previewConfig) }
  }

  private func featureControl(_ feature: FontFeature, config: FontConfiguration) -> some View {
    let selection = Binding(
      get: { config.features[feature.id] ?? feature.defaultValue },
      set: { value in edit("Change typography") { $0.setFeature(feature, value: value, side: side) }
      })
    let binary = feature.options.count == 2 && feature.options.map(\.name) == ["Off", "On"]
    return VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        if feature.isAutomatic {
          HStack(spacing: 7) {
            Text("AUTO").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(verbatim: feature.name).font(.system(size: 12))
          }.help("Applied automatically by the text shaping engine")
        } else if binary {
          Toggle(
            feature.name,
            isOn: Binding(
              get: { selection.wrappedValue == feature.options[1].value },
              set: { selection.wrappedValue = feature.options[$0 ? 1 : 0].value }
            )
          ).toggleStyle(.checkbox).font(.system(size: 12))
            .accessibilityIdentifier("\(side.fontName) feature \(feature.id)")
        } else {
          Text(verbatim: feature.name).font(.system(size: 12))
        }
        Spacer(minLength: 0)
        if feature.id.hasPrefix("ot.") {
          Text(verbatim: String(feature.id.dropFirst(3))).font(
            .system(size: 10, design: .monospaced)
          )
          .foregroundStyle(.secondary)
        }
      }
      if !feature.isAutomatic && !binary {
        Picker(feature.name, selection: selection) {
          ForEach(feature.options, id: \.value) { Text(verbatim: $0.name).tag($0.value) }
        }.labelsHidden().accessibilityIdentifier("\(side.fontName) feature \(feature.id)")
      }
      if !feature.isAutomatic {
        featurePreview(feature)
      }
    }
  }

  @ViewBuilder
  private func featurePreview(_ feature: FontFeature)
    -> some View
  {
    Group {
      if let result = previews.result, result.config == previewConfig {
        if let preview = result.previews[feature.id] {
          HStack(spacing: 8) {
            FontPreviewText(config: preview.before, text: preview.text)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            FontPreviewText(config: preview.after, text: preview.text)
          }.accessibilityLabel("Before and after: \(preview.text)")
        } else {
          Text("No preview available").font(.caption).foregroundStyle(.secondary)
            .help(
              "The example text does not change with this feature in the current font settings.")
        }
      } else {
        Color.clear.accessibilityHidden(true)
      }
    }.frame(height: 30)
  }
  private func edit(_ name: String, _ body: (inout Comparison) -> Void) {
    model.edit(name, undoManager: undoManager, body)
  }
}
