import SwiftUI
import TypefaceCore

struct MatchSheet: View {
  @ObservedObject var document: WorkbenchDocument
  @Environment(\.dismiss) private var dismiss
  @Environment(\.undoManager) private var undoManager
  @State private var options = MatchOptions()

  private var proposed: FontConfiguration? {
    Matching.proposal(document.comparison, options: options, catalog: document.catalog)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Match").font(.title2)
        Spacer()
        Button("Cancel matching", systemImage: "xmark.circle.fill") { dismiss() }
          .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
      }
      if let proposed, let b = document.comparison.b {
        HStack {
          Text(verbatim: document.comparison.a.face.family).fontWeight(.semibold)
          Spacer()
          Image(systemName: "arrow.right").foregroundStyle(.secondary)
          Spacer()
          Text(verbatim: b.face.family).fontWeight(.semibold)
        }.padding(14).frame(maxWidth: .infinity).background(.white)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(WorkbenchStyle.border))
        option(
          "Weight", value: $options.weight, before: weightDescription(b),
          after: weightDescription(suggestion(including: \.weight) ?? b)
        )
        option(
          "x-height", value: $options.xHeight, before: "\(number(b.size)) pt",
          after: "\(number(suggestion(including: \.xHeight)?.size ?? b.size)) pt")
        option(
          "Tracking", value: $options.tracking, before: "\(number(b.tracking, digits: 3)) em",
          after:
            "\(number(suggestion(including: \.tracking)?.tracking ?? b.tracking, digits: 3)) em")
        HStack(spacing: 16) {
          preview(document.comparison.a, label: "Reference A")
          preview(proposed, label: "Proposed B")
        }.padding(14).frame(height: 110).background(.white).clipShape(
          RoundedRectangle(cornerRadius: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(WorkbenchStyle.border))
        Text(
          "Weight uses the nearest numeric weight. It is a heuristic, not a perceptual match. x-height and tracking use measured font data."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Choose two installed fonts to preview matching.").foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply") {
          if let proposed {
            document.edit("Match fonts", undoManager: undoManager) {
              $0.b = proposed
              $0.calibrate()
            }
          }
          dismiss()
        }.keyboardShortcut(.defaultAction).disabled(options.isEmpty || proposed == nil)
      }
    }.padding(24).frame(width: 470).background(WorkbenchStyle.sheet)
      .environment(\.colorScheme, .light).preferredColorScheme(.light)
  }

  private func option(_ title: String, value: Binding<Bool>, before: String, after: String)
    -> some View
  {
    HStack {
      Toggle(title, isOn: value).toggleStyle(.checkbox)
      Spacer()
      Text(verbatim: before == after ? after : "\(before) → \(after)").monospacedDigit()
        .foregroundStyle(.secondary)
    }.padding(14).background(.white).clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(WorkbenchStyle.border))
  }

  private func weightDescription(_ config: FontConfiguration) -> String {
    config.face.axes.contains { $0.tag == "wght" } ? number(config.weight) : config.face.style
  }

  private func suggestion(including option: WritableKeyPath<MatchOptions, Bool>)
    -> FontConfiguration?
  {
    var choices = options
    choices[keyPath: option] = true
    return Matching.proposal(document.comparison, options: choices, catalog: document.catalog)
  }

  private func preview(_ config: FontConfiguration, label: String) -> some View {
    var scaled = config
    scaled.size = 29 * config.size / document.comparison.a.size
    return VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: "\(number(config.weight)) · \(number(config.size)) pt")
        .font(.caption).foregroundStyle(.secondary).accessibilityLabel(label)
      SpecimenText(config: scaled, text: "Hamburg", inset: .zero)
    }.frame(maxWidth: .infinity)
  }
}
