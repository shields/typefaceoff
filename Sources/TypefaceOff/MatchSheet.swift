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
    VStack(alignment: .leading, spacing: 20) {
      Text("Match font B to A").font(.title2)
      if let b = document.comparison.b, let proposed {
        Text(verbatim: "\(document.comparison.a.face.family) → \(b.face.family)").foregroundStyle(
          .secondary)
        option(
          "Weight", value: $options.weight, before: number(b.weight), after: number(proposed.weight)
        )
        option(
          "x-height", value: $options.xHeight, before: "\(number(b.size)) pt",
          after: "\(number(proposed.size)) pt")
        option(
          "Tracking", value: $options.tracking, before: "\(number(b.tracking, digits: 3)) em",
          after: "\(number(proposed.tracking, digits: 3)) em")
        HStack(spacing: 1) {
          preview(document.comparison.a, label: "Reference A")
          preview(proposed, label: "Proposed B")
        }.frame(height: 130).background(.white.opacity(0.1)).clipShape(
          RoundedRectangle(cornerRadius: 6))
        Text(
          "Weight uses the nearest numeric weight. It is a heuristic, not a perceptual match. x-height and tracking use measured font data."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
    }.padding(24).frame(width: 530).background(Color(white: 0.17))
  }

  private func option(_ title: String, value: Binding<Bool>, before: String, after: String)
    -> some View
  {
    HStack {
      Toggle(title, isOn: value).toggleStyle(.checkbox)
      Spacer()
      Text(verbatim: before == after ? after : "\(before) → \(after)").monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }

  private func preview(_ config: FontConfiguration, label: String) -> some View {
    var scaled = config
    scaled.size = 29 * config.size / document.comparison.a.size
    return VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
      SpecimenText(config: scaled, text: "Hamburg")
    }.padding(12).frame(maxWidth: .infinity)
  }
}
