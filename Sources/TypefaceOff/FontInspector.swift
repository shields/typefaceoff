import SwiftUI
import TypefaceCore

struct FontInspector: View {
  @ObservedObject var document: WorkbenchDocument
  let side: Side
  @Environment(\.undoManager) private var undoManager
  @State private var familySearch = ""
  @State private var choosingFamily = false
  @State private var cachedFaces: [FontFace] = []
  @State private var collapsedGroups: Set<FontFeature.Group> = [.automatic]

  private var config: FontConfiguration? { document.comparison[side] }

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
        }.buttonStyle(.plain).accessibilityLabel("Font \(side.rawValue.uppercased()) family")
          .popover(isPresented: $choosingFamily) { familyPicker }
        if let config, FontRenderer.isAvailable(config) {
          Picker(
            "Style",
            selection: Binding(
              get: { config.postScriptName },
              set: { name in
                edit("Change style") {
                  $0.selectFace(
                    FontFace(postScriptName: name), side: side, catalog: document.catalog)
                }
              })
          ) {
            ForEach(cachedFaces) { Text(verbatim: $0.style).tag($0.id) }
          }.labelsHidden()
        }
      }.padding(18)
      Divider()
      if let config, FontRenderer.isAvailable(config) {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            HStack {
              Text("Appearance").font(.headline)
              Spacer()
              Button("Reset appearance", systemImage: "arrow.counterclockwise") {
                resetAppearance()
              }.labelStyle(.iconOnly)
              Button(
                document.comparison.appearanceLocked ? "Unlock appearance" : "Lock appearance",
                systemImage: document.comparison.appearanceLocked ? "lock.fill" : "lock.open"
              ) {
                edit("Link appearance") {
                  $0.appearanceLocked.toggle()
                  $0.calibrate()
                }
              }.labelStyle(.iconOnly).disabled(document.comparison.b == nil)
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
                range: axis.minimum...axis.maximum, defaultValue: axis.defaultValue)
            }
            numericControl(
              "Size", property: .size, value: config.size, range: 10...144, step: 0.1,
              defaultValue: 22, unit: "pt")
            numericControl(
              "Tracking", property: .tracking, value: config.tracking, range: -0.12...0.15,
              step: 0.001, defaultValue: 0, unit: "em")
            Divider()
            HStack {
              Text("Typography").font(.headline)
              Spacer()
              Button("Reset typography", systemImage: "arrow.counterclockwise") {
                edit("Reset typography") { $0[side]?.features = [:] }
              }
              .labelStyle(.iconOnly).buttonStyle(.borderless)
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
          }.padding(18)
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
    .onChange(of: config?.face.family, initial: true) { _, family in
      cachedFaces = family.map { document.catalog.faces(in: $0) } ?? []
    }
  }

  private var familyPicker: some View {
    VStack(spacing: 10) {
      TextField("Search installed fonts", text: $familySearch).textFieldStyle(.roundedBorder)
        .padding([.top, .horizontal])
      List {
        if side == .b { Button("None") { choose(nil) }.buttonStyle(.plain) }
        ForEach(
          document.catalog.families.filter {
            familySearch.isEmpty || $0.localizedCaseInsensitiveContains(familySearch)
          }, id: \.self
        ) { family in
          Button {
            choose(family)
          } label: {
            Text(verbatim: family).frame(maxWidth: .infinity, alignment: .leading).contentShape(
              Rectangle())
          }.buttonStyle(.plain)
        }
      }
    }.frame(width: 300, height: 400)
  }

  private func numericControl(
    _ title: String, property: AppearanceProperty, value: Double, range: ClosedRange<Double>,
    step: Double? = nil, defaultValue: Double, unit: String = ""
  ) -> some View {
    let binding = Binding(
      get: { value },
      set: { value in
        edit("Adjust \(title.lowercased())") {
          $0.set(property, to: value, side: side, catalog: document.catalog)
        }
      })
    return VStack(spacing: 8) {
      HStack(spacing: 6) {
        Text(verbatim: title)
        Button("Reset \(title.lowercased())", systemImage: "arrow.counterclockwise") {
          binding.wrappedValue = defaultValue
        }
        .labelStyle(.iconOnly).buttonStyle(.borderless).font(.caption).disabled(
          value == defaultValue)
        Spacer(minLength: 0)
        TextField(title, value: binding, format: .number.precision(.fractionLength(0...3)))
          .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 62)
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
            document.beginContinuousEdit("Adjust \(title.lowercased())")
          } else {
            document.endContinuousEdit(undoManager: undoManager)
          }
        }
      ).accessibilityLabel("Font \(side.rawValue.uppercased()) \(title)")
    }.font(.system(size: 12))
  }

  private func metric(_ label: String, _ value: String) -> some View {
    HStack {
      Text(verbatim: label).foregroundStyle(.secondary)
      Spacer()
      Text(verbatim: value).monospacedDigit()
    }
  }

  private func featureControl(_ feature: FontFeature, config: FontConfiguration) -> some View {
    let selection = Binding(
      get: { config.features[feature.id] ?? feature.defaultValue },
      set: { value in edit("Change typography") { $0.setFeature(feature, value: value, side: side) }
      })
    let binary = feature.options.count == 2 && feature.options.map(\.name) == ["Off", "On"]
    return VStack(alignment: .leading, spacing: 7) {
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
      } else {
        Text(verbatim: feature.name).font(.system(size: 12))
        Picker(feature.name, selection: selection) {
          ForEach(feature.options, id: \.value) { Text(verbatim: $0.name).tag($0.value) }
        }.labelsHidden()
      }
      if let sample = feature.sample ?? featureSample(feature.id), !sample.isEmpty {
        featurePreview(feature, config: config, sample: sample)
      }
      if feature.id.hasPrefix("ot.") {
        Text(verbatim: String(feature.id.dropFirst(3))).font(.system(size: 10, design: .monospaced))
          .foregroundStyle(.secondary)
      }
    }
  }

  private func featurePreview(_ feature: FontFeature, config: FontConfiguration, sample: String)
    -> some View
  {
    var before = config
    var after = config
    before.features[feature.id] = feature.options.first?.value
    let selected = config.features[feature.id] ?? feature.defaultValue
    after.features[feature.id] =
      selected == feature.options.first?.value ? feature.options.last?.value : selected
    return HStack(spacing: 8) {
      Text(verbatim: sample).font(Font(FontRenderer.font(before, size: 21)))
      Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
      Text(verbatim: sample).font(Font(FontRenderer.font(after, size: 21)))
    }.lineLimit(1).accessibilityLabel("Before and after: \(sample)")
  }

  private func featureSample(_ id: String) -> String? {
    if id.hasPrefix("ot.cv") || id.hasPrefix("ot.ss") { return "ag" }
    return [
      "ot.liga": "fi fl", "aat.1.2": "fi fl", "ot.dlig": "st", "ot.frac": "1/2", "ot.zero": "0",
      "ot.tnum": "1820", "ot.pnum": "1820", "aat.6": "1820", "aat.17": "!?", "ot.case": "(A)",
    ][id]
  }
  private func edit(_ name: String, _ body: (inout Comparison) -> Void) {
    document.edit(name, undoManager: undoManager, body)
  }
  private func choose(_ family: String?) {
    edit("Change font") { $0.selectFamily(family, side: side, catalog: document.catalog) }
    choosingFamily = false
  }
  private func resetAppearance() {
    edit("Reset appearance") {
      $0.resetAppearance(side: side, catalog: document.catalog)
    }
  }
}
