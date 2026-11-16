import SwiftUI
import TypefaceCore

@MainActor final class ComparisonInspectorState: ObservableObject {
  enum Section: String { case appearance, typography }
  @Published var collapsedGroups: Set<FontFeature.Group> = [.automatic]
  @Published var selectedFeature: String?
  @Published var scroll = ScrollPosition(idType: Section.self)
  var scrollOffset: CGFloat = 0

  func reveal(_ section: Section) { scroll.scrollTo(id: section, anchor: .top) }

  func preserveScroll() {
    // Restoring a section identity loses the position within that section.
    scroll = ScrollPosition(idType: Section.self, y: scrollOffset)
  }
}

struct ComparisonInspector: View {
  @ObservedObject var model: WorkbenchModel
  @ObservedObject var state: ComparisonInspectorState
  var preview: FontConfiguration? = nil
  @Environment(\.workbenchUndoManager) private var undoManager
  @Environment(\.locale) private var locale

  private var comparison: Comparison {
    var comparison = model.comparison
    if let preview { comparison.b = preview }
    return comparison
  }
  private var settings: [SpecificationSetting] {
    SpecificationSetting.settings(
      a: installed(.a)?.face.axes ?? [], b: installed(.b)?.face.axes ?? [])
  }

  var body: some View {
    VStack(spacing: 0) {
      facts
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          appearance.id(ComparisonInspectorState.Section.appearance)
          Rectangle().fill(WorkbenchStyle.hairline).frame(height: 1)
          ComparisonTypography(model: model, state: state, preview: preview)
            .id(ComparisonInspectorState.Section.typography)
        }.scrollTargetLayout()
          .onGeometryChange(for: CGFloat.self) {
            -$0.frame(in: .scrollView).minY
          } action: {
            state.scrollOffset = $0
          }
          .padding(.horizontal, 24).padding(.vertical, 12)
          .scrollAreaIdentifier("Comparison inspector scroll area")
      }.scrollPosition($state.scroll)
        .onDisappear { state.preserveScroll() }
    }.frame(width: 320).background(WorkbenchStyle.paper)
      .font(.system(size: 13)).foregroundStyle(WorkbenchStyle.ink)
      .tint(WorkbenchStyle.ink)
  }

  private var facts: some View {
    VStack(spacing: 0) {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 1) {
        GridRow {
          Color.clear.frame(width: 94, height: 20)
          letter(.a)
          letter(.b)
        }
        fact("Units/em") { String($0.face.unitsPerEm) }
        fact("x-height") { config in
          FontRenderer.xHeight(config: config).map {
            SpecificationNumber.format(
              $0 / Double(config.face.unitsPerEm), precision: 3, locale: locale) + " em"
          } ?? "—"
        }
        if [installed(.a), installed(.b)].contains(where: { $0?.face.axes.isEmpty == true }) {
          fact("Weight") {
            $0.face.axes.isEmpty
              ? SpecificationNumber.format($0.weight, precision: 0, locale: locale) : "—"
          }
        }
      }.padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
      Rectangle().fill(WorkbenchStyle.hairline).frame(height: 1)
    }.frame(height: 106).padding(.horizontal, 24)
  }

  private func fact(_ title: String, value: @escaping (FontConfiguration) -> String) -> some View {
    GridRow {
      Text(verbatim: title).foregroundStyle(WorkbenchStyle.secondaryInk)
      ForEach([Side.a, .b], id: \.self) { side in
        Text(verbatim: installed(side).map(value) ?? "—")
          .monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
          .accessibilityLabel("\(side.fontName) \(title) fact")
      }
    }.frame(height: 20)
  }

  private var appearance: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text("Appearance").fontWeight(.semibold)
        if comparison.hasAppearanceChanges(catalog: model.catalog) {
          Button("Reset") {
            edit("Reset appearance") {
              $0.resetAppearance(catalog: model.catalog)
            }
          }.buttonStyle(.bordered).controlSize(.small)
            .accessibilityIdentifier("Reset appearance section")
        }
        Spacer(minLength: 0)
        Toggle(
          "Link A and B",
          isOn: Binding(
            get: { comparison.appearanceLocked },
            set: { locked in
              edit("Link appearance") {
                $0.appearanceLocked = locked
                $0.calibrate()
              }
            })
        ).toggleStyle(.checkbox).controlSize(.small).fixedSize()
          .accessibilityIdentifier("Inspector appearance link")
          .disabled(installed(.a) == nil || installed(.b) == nil)
      }.frame(height: 24)
      ForEach(settings, id: \.self) { setting in
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 4) {
            Text(verbatim: title(setting)).foregroundStyle(WorkbenchStyle.secondaryInk)
            SpecificationRelationMenu(model: model, setting: setting, identifier: "Inspector")
            Spacer()
            if changed(setting) {
              ResetButton(label: "Reset \(title(setting).lowercased())") {
                edit("Reset \(title(setting).lowercased())") {
                  setting.reset(in: &$0, catalog: model.catalog)
                }
              }.buttonStyle(.plain).frame(width: 20, height: 20)
                .accessibilityIdentifier("Reset paired \(title(setting).lowercased())")
            }
          }.frame(height: 20)
          ForEach([Side.a, .b], id: \.self) { side in
            if let config = installed(side), let rules = setting.rules(for: config) {
              settingRow(setting, rules: rules, config: config, side: side)
            }
          }
        }
      }
    }
  }

  private func settingRow(
    _ setting: SpecificationSetting, rules: SpecificationValue, config: FontConfiguration,
    side: Side
  ) -> some View {
    let configs = [installed(.a), installed(.b)].compactMap { $0 }.filter {
      setting.rules(for: $0) != nil
    }
    let precision = SpecificationNumber.precision(
      configs.map { setting.value(in: $0) },
      computed: setting == .leading && configs.contains { $0.leading == nil })
    let unit = setting == .tracking ? "em" : setting == .size || setting == .leading ? "pt" : ""
    return HStack(spacing: 6) {
      letter(side).frame(width: 14)
      SpecificationSlider(
        setting: setting, rules: rules, value: setting.value(in: config),
        automatic: setting == .leading && config.leading == nil,
        identifier: "\(side.fontName) \(title(setting))",
        change: { _ = apply(.number($0), setting: setting, side: side, both: false) },
        editing: { editing in
          if editing {
            model.beginContinuousEdit("Adjust \(title(setting).lowercased())")
          } else {
            model.endContinuousEdit(undoManager: undoManager)
          }
        })
      SpecificationField(
        label: "\(side.fontName) inspector \(title(setting).lowercased())",
        identifier: "\(side.fontName) Inspector \(title(setting)) field",
        value: setting.value(in: config), precision: precision, unit: unit,
        automatic: setting == .leading && config.leading == nil, rules: rules, numberWidth: 52,
        showsAutomaticLabel: false,
        commit: { apply($0, setting: setting, side: side, both: $1) }
      ).frame(width: 82, height: 24)
      if setting == .leading {
        Toggle(
          "Auto",
          isOn: Binding(
            get: { config.leading == nil },
            set: { automatic in
              _ = apply(
                automatic ? .automatic : .number(FontRenderer.automaticLeading(config)),
                setting: setting, side: side, both: false)
            })
        ).toggleStyle(.checkbox).controlSize(.small).font(.system(size: 11)).fixedSize()
          .frame(width: 50, alignment: .leading)
          .accessibilityIdentifier("\(side.fontName) Auto leading")
      } else {
        Color.clear.frame(width: 50, height: 1)
      }
    }.frame(height: 24)
  }

  private func changed(_ setting: SpecificationSetting) -> Bool {
    [installed(.a), installed(.b)].compactMap { $0 }.contains {
      setting.rules(for: $0) != nil && setting.isChanged(in: $0)
    }
  }

  private func title(_ setting: SpecificationSetting) -> String {
    switch setting {
    case .size: "Size"
    case .leading: "Leading"
    case .tracking: "Tracking"
    case .axis(let id):
      (installed(.a)?.face.axes.first { $0.id == id }
        ?? installed(.b)!.face.axes.first { $0.id == id })!.name
    }
  }

  private func installed(_ side: Side) -> FontConfiguration? {
    comparison[side].flatMap { FontRenderer.isAvailable($0) ? $0 : nil }
  }

  private func letter(_ side: Side) -> some View {
    Text(side == .a ? "A" : "B").fontWeight(.semibold)
      .foregroundStyle(Color(nsColor: side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue))
  }

  private func apply(
    _ entry: SpecificationValue.Entry, setting: SpecificationSetting, side: Side, both: Bool
  ) -> Bool {
    var accepted = false
    edit("Adjust \(title(setting).lowercased())") {
      accepted = setting.apply(entry, to: &$0, side: side, both: both, catalog: model.catalog)
    }
    return accepted
  }

  private func edit(_ name: String, _ body: (inout Comparison) -> Void) {
    model.edit(name, undoManager: undoManager, body)
  }
}
