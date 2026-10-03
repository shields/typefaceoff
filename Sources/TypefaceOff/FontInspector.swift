import SwiftUI
import TypefaceCore

struct FontInspector: View {
  @ObservedObject var model: WorkbenchModel
  let side: Side
  @Environment(\.workbenchUndoManager) private var undoManager
  @State private var choosingFamily: Bool
  @State private var collapsedGroups: Set<FontFeature.Group>

  init(model: WorkbenchModel, side: Side) {
    self.model = model
    self.side = side
    _choosingFamily = State(initialValue: false)
    _collapsedGroups = State(initialValue: [.automatic])
  }

  private var config: FontConfiguration? { model.comparison[side] }

  private var canResetAppearance: Bool {
    var reset = model.comparison
    reset.resetAppearance(side: side, catalog: model.catalog)
    return reset != model.comparison
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        Button {
          choosingFamily = true
        } label: {
          HStack {
            Text(
              verbatim: config.map {
                FontRenderer.isAvailable($0) ? $0.face.family : $0.postScriptName
              } ?? "None"
            ).font(.headline).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.caption)
          }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(side.fontName) family")
          .popover(isPresented: $choosingFamily) { familyPicker }
        if let config, FontRenderer.isAvailable(config) {
          Picker(
            "Style",
            selection: Binding(
              get: { config.postScriptName },
              set: { name in
                edit("Change style") {
                  $0.selectFace(
                    FontFace(postScriptName: name), side: side, catalog: model.catalog)
                }
              })
          ) {
            ForEach(model.catalog.faces(in: config.face.family)) {
              Text(verbatim: $0.style).tag($0.id)
            }
          }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("\(side.fontName) style")
        }
      }.padding(18)
      Divider()
      if let config, FontRenderer.isAvailable(config) {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            HStack {
              Text("Appearance").font(.headline)
              Spacer()
              // Recorded traces use the explicit reset identifiers and accessibility labels.
              ResetButton(label: "Reset appearance", action: resetAppearance)
                .accessibilityIdentifier("\(side.fontName) Reset appearance")
                .disabled(!canResetAppearance)
                .help("Reset appearance settings for this font and any linked settings")
              Button(
                model.comparison.appearanceLocked ? "Unlock appearance" : "Lock appearance",
                systemImage: model.comparison.appearanceLocked ? "lock.fill" : "lock.slash"
              ) {
                edit("Link appearance") {
                  $0.appearanceLocked.toggle()
                  $0.calibrate()
                }
              }.labelStyle(.iconOnly)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
                .disabled(model.comparison.b == nil)
                .accessibilityIdentifier("\(side.fontName) Appearance lock")
                .help(
                  model.comparison.appearanceLocked
                    ? "Unlock appearance to adjust each font independently"
                    : "Link appearance while preserving the current differences between fonts")
            }.buttonStyle(.borderless)
            if config.face.axes.isEmpty {
              HStack {
                Text("Weight")
                Spacer()
                Text(verbatim: number(config.weight, digits: 0)).foregroundStyle(.secondary)
              }
            }
            ForEach(config.face.axes) { axis in
              let property: AppearanceProperty = axis.tag == "wght" ? .weight : .axis(axis.id)
              numericControl(
                axis.name, property: property, value: config.axes[axis.id] ?? axis.defaultValue,
                range: axis.minimum...axis.maximum, defaultValue: axis.defaultValue,
                unit: axis.tag == "opsz" ? "pt" : "")
            }
            numericControl(
              "Size", property: .size, value: config.size, range: 10...144, step: 0.1,
              defaultValue: 22, unit: "pt")
            leadingControl(config)
            numericControl(
              "Tracking", property: .tracking, value: config.tracking, range: -0.12...0.15,
              step: 0.001, defaultValue: 0, unit: "em")
            Divider()
            FontTypography(
              model: model, side: side, config: config, collapsedGroups: $collapsedGroups)
          }.padding(18).scrollAreaIdentifier("\(side.fontName) inspector scroll area")
        }
        Divider()
        VStack(spacing: 7) {
          metric("Size", "\(number(config.size)) pt")
          metric(
            "x-height",
            FontRenderer.xHeight(config: config).map { "\(number($0, digits: 0)) u" }
              ?? "Unavailable")
          metric("Units/em", String(config.face.unitsPerEm))
        }.font(.system(size: 11)).padding(18)
      } else if let config {
        VStack(alignment: .leading, spacing: 10) {
          Text("Font unavailable").font(.headline).foregroundStyle(.orange)
          Text(verbatim: config.postScriptName).textSelection(.enabled)
          Text("This font is not installed. Choose an installed font above.")
            .foregroundStyle(.secondary)
        }.padding(18)
        Spacer()
      } else {
        Text("Choose a second font to compare.").foregroundStyle(.secondary).padding(18)
        Spacer()
      }
    }
  }

  private var familyPicker: some View {
    FontFamilyPicker(
      families: model.catalog.families, currentFamily: config?.face.family,
      allowsNone: side == .b, ranking: model.familySimilarity,
      reference: side == .b ? model.comparison.a : nil, catalog: model.catalog, choose: choose)
  }

  private func numericControl(
    _ title: String, property: AppearanceProperty, value: Double, range: ClosedRange<Double>,
    step: Double? = nil, defaultValue: Double, unit: String = ""
  ) -> some View {
    let binding = Binding(
      get: { value },
      set: { value in
        edit("Adjust \(title.lowercased())") {
          $0.set(property, to: value, side: side, catalog: model.catalog)
        }
      })
    return VStack(spacing: 8) {
      HStack(spacing: 6) {
        Text(verbatim: title)
        ResetButton(label: "Reset \(title.lowercased())") {
          binding.wrappedValue = defaultValue
        }
        .buttonStyle(.borderless).font(.caption).disabled(
          value == defaultValue
        )
        .accessibilityIdentifier("\(side.fontName) Reset \(title.lowercased())")
        .help("Reset \(title.lowercased()) to its default value")
        Spacer(minLength: 0)
        TextField(title, value: binding, format: .number.precision(.fractionLength(0...3)))
          .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 62)
          .accessibilityIdentifier("\(side.fontName) \(title) field")
        if !unit.isEmpty { Text(verbatim: unit).font(.caption).foregroundStyle(.secondary) }
      }
      Slider(
        value: Binding(
          get: { binding.wrappedValue },
          set: { value in
            binding.wrappedValue = step.map { (value / $0).rounded() * $0 } ?? value
          }), in: range,
        onEditingChanged: { editing in
          if editing {
            model.beginContinuousEdit("Adjust \(title.lowercased())")
          } else {
            model.endContinuousEdit(undoManager: undoManager)
          }
        }
      ).accessibilityLabel("\(side.fontName) \(title)")
        .accessibilityIdentifier("\(side.fontName) \(title)")
    }.font(.system(size: 12))
  }

  private func leadingControl(_ config: FontConfiguration) -> some View {
    let automatic = SpecimenText.automaticLeading(config)
    let binding = Binding(
      get: { config.leading ?? automatic },
      set: { value in
        // Disabling the field can finish an edit after Auto has been restored.
        guard model.comparison[side]?.leading != nil else { return }
        edit("Adjust leading") { $0.setLeading(value, side: side) }
      })
    let range = FontConfiguration.leadingRange
    return VStack(spacing: 8) {
      HStack(spacing: 6) {
        Text("Leading")
        ResetButton(label: "Reset leading") {
          edit("Reset leading") { $0.setLeading(nil, side: side) }
        }
        .buttonStyle(.borderless).font(.caption)
        .disabled(config.leading == nil)
        .accessibilityIdentifier("\(side.fontName) Reset leading")
        .help("Reset leading to Auto using the font’s natural line spacing")
        Spacer(minLength: 0)
        TextField(
          "Leading", value: binding, format: .number.precision(.fractionLength(0...3))
        )
        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 62)
        .accessibilityIdentifier("\(side.fontName) Leading field")
        .disabled(config.leading == nil)
        .help("Baseline-to-baseline distance in points")
        Text("pt").font(.caption).foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        Toggle(
          "Auto",
          isOn: Binding(
            get: { config.leading == nil },
            set: { enabled in
              edit("Toggle automatic leading") {
                $0.setLeading(enabled ? nil : automatic, side: side)
              }
            })
        ).toggleStyle(.checkbox).fixedSize()
          .accessibilityIdentifier("\(side.fontName) Auto leading")
          .help("Use the font’s natural line spacing")
        Slider(
          value: Binding(
            get: { min(range.upperBound, max(range.lowerBound, config.leading ?? automatic)) },
            set: { binding.wrappedValue = ($0 * 10).rounded() / 10 }),
          in: range,
          onEditingChanged: { editing in
            if editing {
              model.beginContinuousEdit("Adjust leading")
            } else {
              model.endContinuousEdit(undoManager: undoManager)
            }
          }
        ).accessibilityLabel("\(side.fontName) Leading")
          .accessibilityIdentifier("\(side.fontName) Leading")
          .disabled(config.leading == nil)
      }
    }.font(.system(size: 12))
  }

  private func metric(_ label: String, _ value: String) -> some View {
    HStack {
      Text(verbatim: label).foregroundStyle(.secondary)
      Spacer()
      Text(verbatim: value).monospacedDigit()
    }
  }

  private func edit(_ name: String, _ body: (inout Comparison) -> Void) {
    model.edit(name, undoManager: undoManager, body)
  }
  private func choose(_ family: String?) {
    edit("Change font") { $0.selectFamily(family, side: side, catalog: model.catalog) }
    choosingFamily = false
  }
  private func resetAppearance() {
    edit("Reset appearance") {
      $0.resetAppearance(side: side, catalog: model.catalog)
    }
  }
}
