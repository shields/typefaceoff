import SwiftUI
import TypefaceCore

struct MatchBand: View {
  let comparison: Comparison
  @ObservedObject var fit: FontFitModel
  let inspectorOpen: Bool
  let cancel: () -> Void
  let apply: () -> Void
  @Environment(\.displayScale) private var scale
  @Environment(\.locale) private var locale

  private var before: FontConfiguration { comparison.b! }
  private var proposal: FontConfiguration { fit.result?.proposed ?? before }
  private var canApply: Bool { !fit.running && fit.result?.improved == true }

  var body: some View {
    GeometryReader { geometry in
      let width = max(960, geometry.size.width)
      let layout = SpecificationLayout(width: width, inspectorOpen: inspectorOpen)
      ZStack(alignment: .topLeading) {
        HStack(spacing: 10) {
          Text("Match").fontWeight(.semibold)
          Text(
            "Optimize one \(Text("B").bold().foregroundColor(Color(nsColor: WorkbenchStyle.blue))) setting at a time. Each search keeps your other preview settings."
          ).font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
        }.fixedSize().frame(height: 20).offset(x: width < 1040 ? 24 : 64, y: 104)
        status.font(.system(size: width < 1120 ? 11 : 13))
          .frame(width: layout.size - 80, height: 20, alignment: .leading).offset(x: 64, y: 128)
        Text(
          "Experimental visual heuristic using the current sample and Latin diagnostics. Lower distance is closer; this is not a confidence percentage."
        ).font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
          .fixedSize().offset(x: 64, y: 154)
        setting(
          .size, title: "Size", id: "size", x: layout.size,
          selected: fit.searchOptions?.size == true
        ) { $0.size = true }
        setting(
          .leading, title: "Leading", id: "leading", x: layout.leading,
          selected: fit.searchOptions?.leading == true
        ) {
          $0.leading = true
        }
        setting(
          .tracking, title: "Tracking", id: "tracking", x: layout.tracking,
          selected: fit.searchOptions?.tracking == true
        ) {
          $0.tracking = true
        }
        if !before.face.axes.isEmpty {
          axes.frame(height: 20).offset(x: layout.weight, y: 104)
          if let axis = before.face.axes.first(where: { $0.tag == "wght" }) {
            was(.axis(axis.id)).offset(x: layout.weight, y: 131)
          }
        }
        if !before.face.features.filter({ !$0.isAutomatic }).isEmpty {
          features.frame(height: 20)
            .offset(
              x: layout.showsTypography ? layout.typography : width - 120,
              y: layout.showsTypography ? 104 : 72)
          if before.features != proposal.features {
            Text(verbatim: "was " + typographySummary(before))
              .font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
              .accessibilityIdentifier("Font B previous typography")
              .offset(x: layout.showsTypography ? layout.typography : width - 120, y: 131)
          }
        }
        HStack(spacing: 8) {
          Button("Cancel", action: cancel).buttonStyle(.bordered)
            .accessibilityIdentifier("Cancel matching").keyboardShortcut(.cancelAction)
          Button(action: apply) {
            Text("Apply").padding(.horizontal, 12).padding(.vertical, 4)
              .foregroundStyle(canApply ? WorkbenchStyle.paper : WorkbenchStyle.secondaryInk)
              .background {
                RoundedRectangle(cornerRadius: 6)
                  .fill(canApply ? WorkbenchStyle.ink : WorkbenchStyle.paper)
              }
              .overlay {
                RoundedRectangle(cornerRadius: 6)
                  .strokeBorder(canApply ? WorkbenchStyle.ink : WorkbenchStyle.hairline)
              }
          }.buttonStyle(.plain).keyboardShortcut(.defaultAction).disabled(!canApply)
        }.frame(width: 136, height: 24, alignment: .trailing)
          .offset(x: width - 160, y: 148)
      }.font(.system(size: 13)).foregroundStyle(WorkbenchStyle.ink)
        .tint(WorkbenchStyle.ink)
    }.frame(height: 182)
  }

  private func setting(
    _ setting: SpecificationSetting, title: String, id: String, x: Double, selected: Bool,
    select: @escaping (inout FontFitOptions) -> Void
  ) -> some View {
    Group {
      Button {
        start(select)
      } label: {
        optimizationLabel(running: fit.running && selected)
      }.buttonStyle(.plain).disabled(fit.running)
        .accessibilityLabel("Optimize \(title.lowercased())")
        .accessibilityIdentifier("Font B Optimize \(id)")
        .help("Optimize only \(title.lowercased()) to match font A")
        .offset(x: x, y: 104)
      was(setting).offset(x: x, y: 131)
    }
  }

  @ViewBuilder private var axes: some View {
    let axes = before.face.axes
    if axes.count == 1 {
      let axis = axes[0]
      Button {
        start { $0.axes = [axis.id] }
      } label: {
        optimizationLabel(running: fit.running && fit.searchOptions?.axes.contains(axis.id) == true)
      }.buttonStyle(.plain).disabled(fit.running)
        .accessibilityLabel("Optimize \(axis.name)")
        .accessibilityIdentifier("Font B Optimize axis \(axis.id)")
    } else {
      Menu {
        ForEach(axes) { axis in
          Button(axis.name) { start { $0.axes = [axis.id] } }
            .accessibilityIdentifier("Font B Optimize axis \(axis.id)")
        }
      } label: {
        optimizationLabel(
          running: fit.running && fit.searchOptions?.axes.isEmpty == false)
      }.menuStyle(.borderlessButton).menuIndicator(fit.running ? .hidden : .visible).fixedSize()
        .disabled(fit.running).accessibilityIdentifier("Font B Optimize axes")
        .accessibilityLabel("Optimize an axis")
    }
  }

  private var features: some View {
    Menu {
      ForEach(before.face.features.filter { !$0.isAutomatic }) { feature in
        Button(feature.name) { start { $0.features = [feature.id] } }
          .accessibilityIdentifier("Font B Optimize feature \(feature.id)")
      }
    } label: {
      optimizationLabel(
        running: fit.running && fit.searchOptions?.features.isEmpty == false)
    }.menuStyle(.borderlessButton).menuIndicator(fit.running ? .hidden : .visible).fixedSize()
      .disabled(fit.running).accessibilityIdentifier("Font B Optimize typography")
      .accessibilityLabel("Optimize a typography feature")
  }

  private func optimizationLabel(running: Bool) -> some View {
    HStack(spacing: running ? 0 : 4) {
      Text(running ? "Optimizing" : "Optimize").font(.system(size: running ? 11 : 13))
      if running {
        ProgressView().controlSize(.mini).scaleEffect(0.5).frame(width: 7, height: 8)
      }
    }.fixedSize().frame(minWidth: 20, minHeight: 20).contentShape(Rectangle())
  }

  @ViewBuilder private var status: some View {
    if let error = fit.error {
      Label(error, systemImage: "exclamationmark.triangle").lineLimit(1).help(error)
        .accessibilityIdentifier("Matching error message")
    } else {
      HStack(spacing: 8) {
        if fit.running {
          ProgressView().controlSize(.mini).frame(width: 12, height: 12)
          Text("Comparing settings…")
        }
        if let result = fit.result {
          if !fit.running && !fit.searchImproved {
            Text("No better value found for this setting.").help(distance(result))
          } else {
            Text(verbatim: distance(result)).monospacedDigit()
              .foregroundStyle(WorkbenchStyle.secondaryInk)
              .accessibilityIdentifier("Matching distance")
          }
        }
        if fit.running {
          Button("Stop") { fit.stop() }.buttonStyle(.bordered).controlSize(.small)
        }
      }.fixedSize()
    }
  }

  private func distance(_ result: FontFitResult) -> String {
    let unit = result.evaluations == 1 ? "evaluation" : "evaluations"
    return "Distance \(result.originalScore.formattedDistance) → \(result.score.formattedDistance)"
      + " · \(result.evaluations) \(unit)"
  }

  @ViewBuilder private func was(_ setting: SpecificationSetting) -> some View {
    if setting.value(in: before) != setting.value(in: proposal)
      || (setting == .leading && before.leading != proposal.leading)
    {
      let configs = [comparison.a, before, proposal]
      let precision = SpecificationNumber.precision(
        configs.map { setting.value(in: $0) },
        computed: setting == .leading && configs.contains { $0.leading == nil })
      let unit =
        setting == .tracking
        ? " em"
        : setting == .size
          || (setting == .leading && before.leading != nil) ? " pt" : ""
      Text(
        verbatim: "was "
          + SpecificationNumber.format(
            setting.value(in: before), precision: precision, locale: locale)
          + unit
      ).font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
        .monospacedDigit()
    }
  }

  private func typographySummary(_ config: FontConfiguration) -> String {
    let count = config.face.features.count {
      (config.features[$0.id] ?? $0.defaultValue) != $0.defaultValue
    }
    return count == 0 ? "Default" : "\(count) \(count == 1 ? "change" : "changes")"
  }

  private func start(_ select: (inout FontFitOptions) -> Void) {
    var options = FontFitOptions(config: before)
    options.axes = []
    options.features = []
    options.tracking = false
    options.size = false
    options.leading = false
    select(&options)
    fit.start(
      .init(
        a: comparison.a, b: before, text: comparison.text, options: options, scale: scale))
  }
}
