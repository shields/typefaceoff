import SwiftUI
import TypefaceCore

struct MatchSheet: View {
  @ObservedObject var model: WorkbenchModel
  @StateObject private var fit: FontFitModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.workbenchUndoManager) private var undoManager
  @Environment(\.displayScale) private var scale
  @State private var options: FontFitOptions
  @State private var typographyExpanded = false

  init(model: WorkbenchModel, fit: FontFitModel = FontFitModel()) {
    self.model = model
    _fit = StateObject(wrappedValue: fit)
    _options = State(initialValue: FontFitOptions(config: model.comparison.b ?? model.comparison.a))
  }

  private var request: FontFitModel.Request? {
    guard let b = model.comparison.b else { return nil }
    return .init(
      a: model.comparison.a, b: b, text: model.comparison.text, options: options, scale: scale)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Match").font(.title2)
        Spacer()
        Button("Cancel matching", systemImage: "xmark.circle.fill") { dismiss() }
          .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
      }
      if let b = model.comparison.b {
        Text(verbatim: "\(model.comparison.a.face.family) → \(b.face.family) · \(b.face.style)")
          .fontWeight(.semibold)
        Text("Choose which B settings can change. Size stays fixed unless enabled.")
          .font(.caption).foregroundStyle(.secondary)
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(b.face.axes) { axis in
              option(
                axis.name, value: membership(axis.id, in: $options.axes),
                before: number(b.axes[axis.id] ?? axis.defaultValue),
                after: number(proposal(b).axes[axis.id] ?? axis.defaultValue))
            }
            option(
              "Tracking", value: $options.tracking,
              before: "\(number(b.tracking, digits: 3)) em",
              after: "\(number(proposal(b).tracking, digits: 3)) em")
            option(
              "Size", value: $options.size, before: "\(number(b.size)) pt",
              after: "\(number(proposal(b).size)) pt")
            DisclosureGroup("Typography", isExpanded: $typographyExpanded) {
              VStack(alignment: .leading, spacing: 10) {
                ForEach(b.face.features.filter { !$0.isAutomatic }) { feature in
                  option(
                    feature.name, value: membership(feature.id, in: $options.features),
                    before: featureName(feature, config: b),
                    after: featureName(feature, config: proposal(b)))
                }
              }.padding(.top, 8)
            }
          }.padding(12)
        }.frame(height: typographyExpanded ? 230 : min(230, 120 + Double(b.face.axes.count) * 32))
          .background(.white).clipShape(RoundedRectangle(cornerRadius: 6))
        HStack(alignment: .top, spacing: 16) {
          preview(model.comparison.a, label: "Reference A")
          preview(proposal(b), label: "Proposed B")
        }.padding(14).frame(height: 120).background(.white)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        if let error = fit.error {
          Text(verbatim: error).foregroundStyle(.orange).fixedSize(
            horizontal: false, vertical: true)
        } else if let result = fit.result {
          Text(
            verbatim:
              "Distance \(result.originalScore.formattedDistance) → \(result.score.formattedDistance) · \(result.evaluations) evaluations"
          )
          .monospacedDigit().font(.caption)
          if !fit.running && !result.improved {
            Text("No better settings found in this search.").font(.caption).foregroundStyle(
              .secondary)
          }
        }
        if fit.running {
          HStack {
            ProgressView().controlSize(.small)
            Text("Comparing settings…").font(.caption)
            Spacer()
            Button("Stop") { fit.stop() }
          }
        }
        Text(
          "Experimental visual heuristic using the current sample and Latin diagnostics. Lower distance is closer; this is not a confidence percentage."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Choose two installed fonts to preview matching.").foregroundStyle(.secondary)
      }
      HStack {
        Button("Refine") { fit.start(request, refine: true) }
          .disabled(fit.running || fit.result == nil || options.isEmpty)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply") {
          if fit.apply(to: model, undoManager: undoManager) { dismiss() }
        }.keyboardShortcut(.defaultAction).disabled(fit.result?.improved != true)
      }
    }.padding(24).frame(width: 540).background(WorkbenchStyle.sheet)
      .environment(\.colorScheme, .light).preferredColorScheme(.light)
      .onChange(of: request, initial: true) { _, request in
        // Publishing FontFitModel's @Published state must not happen synchronously
        // within this view-update callback, so hop to a new main-actor task first.
        Task { @MainActor in fit.start(request) }
      }
      .onDisappear { Task { @MainActor in fit.stop() } }
  }

  private func proposal(_ b: FontConfiguration) -> FontConfiguration { fit.result?.proposed ?? b }

  private func membership<Value: Hashable>(_ value: Value, in set: Binding<Set<Value>>) -> Binding<
    Bool
  > {
    Binding(
      get: { set.wrappedValue.contains(value) },
      set: { enabled in
        if enabled { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) }
      })
  }

  private func featureName(_ feature: FontFeature, config: FontConfiguration) -> String {
    guard let value = config.features[feature.id] else { return "Default" }
    return feature.options.first { $0.value == value }?.name ?? String(value)
  }

  private func option(_ title: String, value: Binding<Bool>, before: String, after: String)
    -> some View
  {
    HStack {
      Toggle(title, isOn: value).toggleStyle(.checkbox)
      Spacer()
      Text(verbatim: before == after ? after : "\(before) → \(after)")
        .monospacedDigit().foregroundStyle(.secondary)
    }
  }

  private func preview(_ config: FontConfiguration, label: String) -> some View {
    // Scale relative to A's size so the two specimens stay visually comparable
    // even after Size fitting moves B away from A's point size.
    var scaled = config
    scaled.size = 29 * config.size / model.comparison.a.size
    return VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: "\(label) · \(number(config.size)) pt")
        .font(.caption).foregroundStyle(.secondary).accessibilityLabel(label)
      SpecimenText(
        config: scaled, text: "Hamburg", inset: .zero, accessibilityName: "\(label) specimen")
    }.frame(maxWidth: .infinity)
  }
}
