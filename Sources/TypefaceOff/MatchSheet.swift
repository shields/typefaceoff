import SwiftUI
import TypefaceCore

struct MatchSheet: View {
  @ObservedObject var model: WorkbenchModel
  @StateObject private var fit: FontFitModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.workbenchUndoManager) private var undoManager
  @Environment(\.displayScale) private var scale

  init(model: WorkbenchModel, fit: FontFitModel = FontFitModel()) {
    self.model = model
    _fit = StateObject(wrappedValue: fit)
  }

  private var request: FontFitModel.Request? {
    guard let b = model.comparison.b else { return nil }
    return .init(
      a: model.comparison.a, b: b, text: model.comparison.text,
      options: FontFitOptions(config: b), scale: scale)
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
        Text("Optimize one B setting at a time. Each search keeps your other preview settings.")
          .font(.caption).foregroundStyle(.secondary)
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(b.face.axes) { axis in
              option(
                axis.name, id: "axis \(axis.id)",
                before: number(b.axes[axis.id] ?? axis.defaultValue),
                after: number(proposal(b).axes[axis.id] ?? axis.defaultValue)
              ) { $0.axes = [axis.id] }
            }
            option(
              "Size", id: "size", before: "\(number(b.size)) pt",
              after: "\(number(proposal(b).size)) pt"
            ) { $0.size = true }
            option(
              "Leading", id: "leading", before: leading(b), after: leading(proposal(b))
            ) { $0.leading = true }
            option(
              "Tracking", id: "tracking",
              before: "\(number(b.tracking, digits: 3)) em",
              after: "\(number(proposal(b).tracking, digits: 3)) em"
            ) { $0.tracking = true }
            Divider()
            Text("Typography").font(.headline)
            ForEach(b.face.features.filter { !$0.isAutomatic }) { feature in
              option(
                feature.name, id: "feature \(feature.id)",
                before: featureName(feature, config: b),
                after: featureName(feature, config: proposal(b))
              ) { $0.features = [feature.id] }
            }
          }.padding(12).scrollAreaIdentifier("Match options scroll area")
        }.frame(height: 230)
          .background(.white).clipShape(RoundedRectangle(cornerRadius: 6))
        HStack(alignment: .top, spacing: 16) {
          preview(model.comparison.a, label: "Reference A")
          preview(proposal(b), label: "Proposed B")
        }.padding(14).frame(height: 120).background(.white)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        status
        Text(
          "Experimental visual heuristic using the current sample and Latin diagnostics. Lower distance is closer; this is not a confidence percentage."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Choose two installed fonts to preview matching.").foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply") {
          if fit.apply(to: model, undoManager: undoManager) { dismiss() }
        }.keyboardShortcut(.defaultAction).disabled(fit.result?.improved != true)
      }
    }.padding(24).frame(width: 540).background(WorkbenchStyle.sheet)
      .environment(\.colorScheme, .light).preferredColorScheme(.light)
      .onChange(of: request) { _, _ in
        // Publishing FontFitModel's @Published state must not happen synchronously
        // within this view-update callback, so hop to a new main-actor task first.
        Task { @MainActor in fit.start(nil) }
      }
      .onDisappear { Task { @MainActor in fit.stop() } }
  }

  private func proposal(_ b: FontConfiguration) -> FontConfiguration { fit.result?.proposed ?? b }

  private func leading(_ config: FontConfiguration) -> String {
    config.leading.map { "\(number($0)) pt" } ?? "Auto"
  }

  private var status: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        if let error = fit.error {
          Text(verbatim: error).foregroundStyle(.orange).fixedSize(
            horizontal: false, vertical: true)
        } else if let result = fit.result {
          let unit = result.evaluations == 1 ? "evaluation" : "evaluations"
          Text(
            verbatim:
              "Distance \(result.originalScore.formattedDistance) → \(result.score.formattedDistance) · \(result.evaluations) \(unit)"
          )
          .monospacedDigit().font(.caption)
          if !fit.running && !fit.searchImproved {
            Text("No better value found for this setting.").font(.caption).foregroundStyle(
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
      }.frame(maxWidth: .infinity, alignment: .leading)
        .scrollAreaIdentifier("Match status scroll area")
    }.frame(height: 64)
  }

  private func featureName(_ feature: FontFeature, config: FontConfiguration) -> String {
    guard let value = config.features[feature.id] else { return "Default" }
    return feature.options.first { $0.value == value }?.name ?? String(value)
  }

  private func option(
    _ title: String, id: String, before: String, after: String,
    select: @escaping (inout FontFitOptions) -> Void
  )
    -> some View
  {
    HStack {
      Text(verbatim: title)
      Spacer()
      Text(verbatim: before == after ? after : "\(before) → \(after)")
        .monospacedDigit().foregroundStyle(.secondary)
      Button("Optimize", systemImage: "equal.square") {
        if let request {
          var options = request.options
          options.axes = []
          options.features = []
          options.tracking = false
          options.size = false
          options.leading = false
          select(&options)
          fit.start(
            .init(a: request.a, b: request.b, text: request.text, options: options, scale: scale))
        }
      }.disabled(fit.running)
        .accessibilityLabel("Optimize \(title)")
        .accessibilityIdentifier("\(Side.b.fontName) Optimize \(id)")
        .help("Optimize only \(title.lowercased()) to match font A")
    }
  }

  private func preview(_ config: FontConfiguration, label: String) -> some View {
    // Scale relative to A's size so the two specimens stay visually comparable
    // even after Size fitting moves B away from A's point size.
    var scaled = config
    scaled.size = 29 * config.size / model.comparison.a.size
    scaled.leading = config.leading.map { 29 * $0 / model.comparison.a.size }
    return VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: "\(label) · \(number(config.size)) pt")
        .font(.caption).foregroundStyle(.secondary).accessibilityLabel(label)
      SpecimenText(
        config: scaled, text: "Hamburg\nHamburg", inset: .zero,
        accessibilityName: "\(label) specimen")
    }.frame(maxWidth: .infinity)
  }
}
