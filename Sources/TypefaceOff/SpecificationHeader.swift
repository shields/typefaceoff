import AppKit
import SwiftUI
import TypefaceCore

struct SpecificationHeader: View {
  @ObservedObject var model: WorkbenchModel
  let inspectorOpen: Bool
  let matching: Bool
  let openInspector: (ComparisonInspectorState.Section) -> Void
  let match: () -> Void
  @Environment(\.workbenchUndoManager) private var undoManager
  @Environment(\.locale) private var locale
  @State private var choosing: Side?
  @Binding private var familyFocus: Side?
  @FocusState private var focusedFamily: Side?

  init(
    model: WorkbenchModel, inspectorOpen: Bool, matching: Bool,
    familyFocus: Binding<Side?> = .constant(nil),
    openInspector: @escaping (ComparisonInspectorState.Section) -> Void, match: @escaping () -> Void
  ) {
    self.model = model
    self.inspectorOpen = inspectorOpen
    self.matching = matching
    self.openInspector = openInspector
    self.match = match
    _choosing = State(initialValue: nil)
    _familyFocus = familyFocus
  }

  private var comparison: Comparison { model.comparison }
  private var canCompare: Bool {
    FontRenderer.isAvailable(comparison.a)
      && comparison.b.map { FontRenderer.isAvailable($0) } == true
  }

  var body: some View {
    GeometryReader { geometry in
      let width = max(960, geometry.size.width)
      let layout = SpecificationLayout(width: width, inspectorOpen: inspectorOpen)
      ZStack(alignment: .topLeading) {
        Button("Swap fonts", systemImage: "arrow.up.arrow.down") {
          edit("Swap fonts") { $0.swap() }
        }
        .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 20, height: 20)
        .disabled(comparison.b == nil || matching).offset(x: 34, y: 6)
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
        ).toggleStyle(.checkbox).controlSize(.small).font(.system(size: 11))
          .accessibilityIdentifier("Header appearance link")
          .disabled(!canCompare || matching)
          .offset(x: 64, y: 6)
        heading("Size", setting: .size).offset(x: layout.size, y: 6)
        heading("Weight", setting: .axis(tagNumber("wght"))).offset(x: layout.weight, y: 6)
        heading("Leading", setting: .leading).offset(x: layout.leading, y: 6)
        heading("Tracking", setting: .tracking).offset(x: layout.tracking, y: 6)
        if layout.showsTypography {
          Text("Typography").font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
            .offset(x: layout.typography, y: 8)
        }
        ForEach([Side.a, .b], id: \.self) { side in
          let y = side == .a ? 36.0 : 72.0
          Text(side == .a ? "A" : "B").font(.system(size: 13, weight: .bold))
            .foregroundStyle(ink(for: side)).offset(x: 40, y: y + 4)
          family(side).frame(width: layout.familyWidth, alignment: .leading)
            .offset(x: 64, y: y - 6)
          if let config = comparison[side], FontRenderer.isAvailable(config) {
            style(config, side: side).frame(width: layout.styleWidth, alignment: .leading)
              .offset(x: layout.style, y: y + 2)
            field(.size, title: "Size", unit: "pt", config: config, side: side)
              .frame(width: 78, height: 24).offset(x: layout.size - 6, y: y)
            weight(config, side: side).frame(
              width: layout.weightFieldWidth, height: 24, alignment: .leading
            )
            .offset(x: layout.weight - 6, y: y)
            otherAxesButton(config, side: side).offset(x: layout.weight, y: y + 20)
            field(.leading, title: "Leading", unit: "pt", config: config, side: side)
              .frame(width: 94, height: 24).offset(x: layout.leading - 6, y: y)
            field(.tracking, title: "Tracking", unit: "em", config: config, side: side)
              .frame(width: layout.trackingFieldWidth, height: 24)
              .offset(x: layout.tracking - 6, y: y)
            if layout.showsTypography {
              typographyButton(config, side: side)
                .offset(x: layout.typography, y: y + 2)
            }
          }
        }
        if !layout.showsTypography {
          Button {
            openInspector(.typography)
          } label: {
            HStack(spacing: 4) {
              Text("Typography")
              Image(systemName: "chevron.down").font(.system(size: 11))
            }.fixedSize().frame(width: 96, height: 24, alignment: .leading)
              .contentShape(Rectangle())
          }.buttonStyle(.plain).disabled(matching)
            .accessibilityIdentifier("Open typography inspector")
            .help("Open the comparison inspector at Typography")
            .offset(x: width - 120, y: 36)
        }
        if canCompare && !matching {
          Button("Match…", action: match).buttonStyle(.bordered)
            .frame(width: 76, height: 24).offset(x: width - 100, y: 72)
        }
        Rectangle().fill(WorkbenchStyle.ink).frame(width: width - 48, height: 1)
          .offset(x: 24, y: 105)
      }.font(.system(size: 13)).foregroundStyle(WorkbenchStyle.ink)
    }.frame(height: 106)
      .onChange(of: familyFocus) { _, side in
        if let side {
          focusedFamily = side
          familyFocus = nil
        }
      }
  }

  private func ink(for side: Side) -> Color {
    guard let config = comparison[side], FontRenderer.isAvailable(config) else {
      return WorkbenchStyle.secondaryInk
    }
    return Color(nsColor: side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue)
  }

  private func family(_ side: Side) -> some View {
    let config = comparison[side]
    let installed = config.map { FontRenderer.isAvailable($0) } == true
    let name = config.map { installed ? $0.face.family : $0.postScriptName } ?? "None"
    let font: Font =
      if let config, installed && FontRenderer.supports(name, config: config) {
        .custom(config.postScriptName, size: 26)
      } else { .system(size: 26) }
    return Button {
      choosing = side
    } label: {
      HStack(spacing: 8) {
        Text(verbatim: name).font(font).lineLimit(1).truncationMode(.middle)
          .foregroundStyle(installed ? WorkbenchStyle.ink : WorkbenchStyle.secondaryInk)
        if config != nil && !installed {
          Image(systemName: "exclamationmark.triangle")
          Text("Not installed").font(.system(size: 13))
        }
        Image(systemName: "chevron.down").font(.system(size: 11))
      }.frame(height: 28).contentShape(Rectangle())
    }.buttonStyle(.plain).focusable(!matching)
      .onKeyPress(.return) {
        choosing = side
        return .handled
      }.disabled(matching)
      .focused($focusedFamily, equals: side)
      .accessibilityLabel("\(side.fontName) family")
      .accessibilityValue(name)
      .popover(isPresented: Binding(get: { choosing == side }, set: { if !$0 { choosing = nil } }))
    {
      FontFamilyPicker(
        families: model.catalog.families, currentFamily: config?.face.family,
        allowsNone: side == .b, ranking: model.familySimilarity,
        reference: side == .b ? comparison.a : nil, catalog: model.catalog
      ) { family in
        edit("Change font") { $0.selectFamily(family, side: side, catalog: model.catalog) }
        choosing = nil
      }.preferredColorScheme(.light)
    }
  }

  private func style(_ config: FontConfiguration, side: Side) -> some View {
    SpecificationStylePicker(
      faces: model.catalog.faces(in: config.face.family), selected: config.postScriptName,
      identifier: "\(side.fontName) style", enabled: !matching
    ) { name in
      edit("Change style") {
        $0.selectFace(.named(name), side: side, catalog: model.catalog)
      }
    }.fixedSize().frame(height: 24)
  }

  @ViewBuilder private func weight(_ config: FontConfiguration, side: Side) -> some View {
    let setting = SpecificationSetting.axis(tagNumber("wght"))
    if setting.rules(for: config) != nil {
      field(setting, title: "Weight", unit: "", config: config, side: side)
    } else {
      Text(verbatim: SpecificationNumber.format(config.weight, precision: 0, locale: locale))
        .monospacedDigit().foregroundStyle(WorkbenchStyle.secondaryInk).padding(.leading, 6)
    }
  }

  private func field(
    _ setting: SpecificationSetting, title: String, unit: String,
    config: FontConfiguration, side: Side
  ) -> some View {
    let configs = [comparison.a, comparison.b].compactMap { $0 }.filter {
      FontRenderer.isAvailable($0)
    }
    let values = configs.map { setting.value(in: $0) }
    let precision = SpecificationNumber.precision(
      values, computed: setting == .leading && configs.contains { $0.leading == nil })
    let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    let numberWidth =
      values.map {
        (SpecificationNumber.format($0, precision: precision, locale: locale) as NSString)
          .size(withAttributes: [.font: font]).width
      }.max()!
    return SpecificationField(
      label: "\(side.fontName) \(title.lowercased())",
      identifier: "\(side.fontName) \(title) field",
      value: setting.value(in: config), precision: precision, unit: unit,
      automatic: setting == .leading && config.leading == nil,
      rules: setting.rules(for: config)!, numberWidth: ceil(numberWidth), enabled: !matching
    ) { entry, both in
      var accepted = false
      edit("Adjust \(title.lowercased())") {
        accepted = setting.apply(entry, to: &$0, side: side, both: both, catalog: model.catalog)
      }
      return accepted
    }
  }

  @ViewBuilder private func otherAxesButton(_ config: FontConfiguration, side: Side) -> some View {
    let changes = config.face.axes.filter {
      $0.tag != "wght" && SpecificationSetting.axis($0.id).isChanged(in: config)
    }.count
    if changes > 0 {
      Button {
        openInspector(.appearance)
      } label: {
        Text(verbatim: "+\(changes) \(changes == 1 ? "axis" : "axes")")
      }.buttonStyle(.plain).font(.system(size: 11)).frame(height: 12)
        .disabled(matching).accessibilityLabel("\(side.fontName) other axes")
        .accessibilityValue(
          "\(changes) changed \(changes == 1 ? "axis" : "axes"), opens Appearance")
    }
  }

  private func typographyButton(_ config: FontConfiguration, side: Side) -> some View {
    let changes = config.face.features.filter { feature in
      (config.features[feature.id] ?? feature.defaultValue) != feature.defaultValue
    }.count
    let title = changes == 0 ? "Default" : "\(changes) \(changes == 1 ? "change" : "changes")"
    return Button {
      openInspector(.typography)
    } label: {
      HStack(spacing: 4) {
        Text(verbatim: title)
        Image(systemName: "chevron.down").font(.system(size: 11))
      }.frame(minHeight: 20, alignment: .top).contentShape(Rectangle())
    }.buttonStyle(.plain).disabled(matching)
      .accessibilityLabel("\(side.fontName) typography")
      .accessibilityValue("\(title), opens the inspector")
  }

  private func heading(_ title: String, setting: SpecificationSetting) -> some View {
    HStack(spacing: 4) {
      Text(verbatim: title).foregroundStyle(WorkbenchStyle.secondaryInk)
      SpecificationRelationMenu(model: model, setting: setting, identifier: "Header")
        .disabled(matching)
    }.font(.system(size: 11)).frame(height: 20)
  }

  private func edit(_ name: String, _ body: (inout Comparison) -> Void) {
    model.edit(name, undoManager: undoManager, body)
  }
}

private struct SpecificationStylePicker: NSViewRepresentable {
  let faces: [FontFace]
  let selected: String
  let identifier: String
  let enabled: Bool
  let select: (String) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(select: select) }

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
    context.coordinator.select = select
    button.removeAllItems()
    for face in faces {
      let item = NSMenuItem(title: face.style, action: nil, keyEquivalent: "")
      item.representedObject = face.id
      button.menu!.addItem(item)
      if face.id == selected { button.select(item) }
    }
    button.isEnabled = enabled
    button.setAccessibilityIdentifier(identifier)
    button.setAccessibilityLabel(identifier)
  }

  @MainActor final class Coordinator: NSObject {
    var select: (String) -> Void
    init(select: @escaping (String) -> Void) { self.select = select }

    @objc func choose(_ sender: NSPopUpButton) {
      select(sender.selectedItem!.representedObject as! String)
    }
  }
}
