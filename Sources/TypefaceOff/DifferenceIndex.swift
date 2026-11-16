import SwiftUI
import TypefaceCore

struct DifferenceIndex: View {
  @ObservedObject var model: WorkbenchModel
  @ObservedObject var ranking: RankingModel
  let inspectorOpen: Bool
  let select: (String) -> Void
  let navigate: (Int) -> Void
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  private var comparison: Comparison { model.comparison }
  private var items: [RankedDifference] {
    Differences.scored(
      ranking.scores, shape: comparison.shape, spacing: comparison.spacing,
      frequency: comparison.frequency)
  }
  private var canCompare: Bool {
    FontRenderer.isAvailable(comparison.a)
      && comparison.b.map { FontRenderer.isAvailable($0) } == true
  }

  var body: some View {
    GeometryReader { geometry in
      let width = max(960, geometry.size.width)
      let layout = SpecificationLayout(width: width, inspectorOpen: inspectorOpen)
      let controlX = min(layout.indexControls, width - (differentiateWithoutColor ? 304 : 280))
      ZStack(alignment: .topLeading) {
        Rectangle().fill(WorkbenchStyle.hairline).frame(height: 1)
          .padding(.horizontal, 24).offset(y: 75)
        if canCompare {
          if items.isEmpty && !ranking.comparing {
            Text("No shared characters to compare.").foregroundStyle(WorkbenchStyle.secondaryInk)
              .offset(x: 64, y: 27)
          } else {
            strip.frame(width: controlX - 64, height: 76).offset(x: 64)
          }
          controls.frame(width: width - controlX - 24).offset(x: controlX, y: 9)
        } else {
          Text(
            comparison.b == nil
              ? "Choose a second font to compare."
              : "\(FontRenderer.isAvailable(comparison.a) ? "B" : "A") is not installed. Choose an installed font to compare."
          )
          .foregroundStyle(WorkbenchStyle.secondaryInk).offset(x: 64, y: 27)
        }
      }.font(.system(size: 13)).foregroundStyle(WorkbenchStyle.ink)
    }.frame(height: 76)
  }

  private var controls: some View {
    VStack(spacing: 8) {
      HStack(spacing: 5) {
        Text("Differences").foregroundStyle(WorkbenchStyle.secondaryInk)
        if ranking.comparing {
          ProgressView().controlSize(.mini).accessibilityLabel("Comparing glyphs")
        }
        Spacer(minLength: 4)
        if differentiateWithoutColor { hatch(rising: true) }
        Text("Only A").foregroundStyle(Color(nsColor: WorkbenchStyle.red)).fontWeight(.semibold)
        Text("Shared").fontWeight(.semibold)
        if differentiateWithoutColor { hatch(rising: false) }
        Text("Only B").foregroundStyle(Color(nsColor: WorkbenchStyle.blue)).fontWeight(.semibold)
      }.font(.system(size: 11))
      HStack(spacing: 0) {
        Toggle("Shape", isOn: binding(\.shape)).toggleStyle(.checkbox)
        Spacer(minLength: 4)
        Toggle("Spacing", isOn: binding(\.spacing)).toggleStyle(.checkbox)
        Spacer(minLength: 4)
        Toggle("Frequency", isOn: binding(\.frequency)).toggleStyle(.checkbox)
        Rectangle().fill(WorkbenchStyle.track).frame(width: 12, height: 2)
          .overlay(alignment: .leading) {
            Rectangle().fill(WorkbenchStyle.ink).frame(width: 7, height: 2)
          }
          .padding(.leading, 4).accessibilityHidden(true)
      }.controlSize(.small)
    }
  }

  private func hatch(rising: Bool) -> some View {
    Canvas { context, size in
      context.withCGContext { drawing in
        drawing.translateBy(x: 0, y: size.height)
        drawing.scaleBy(x: 1, y: -1)
        ComparisonHatch(rising: rising).draw(
          in: drawing, rect: CGRect(origin: .zero, size: size))
      }
    }.background(Color(nsColor: rising ? WorkbenchStyle.red : WorkbenchStyle.blue))
      .frame(width: 9, height: 9).accessibilityHidden(true)
  }

  private var strip: some View {
    let comparison = comparison
    let items = self.items
    let maximum = items.map(\.measured).max() ?? 0
    return DifferenceStrip(
      count: items.count,
      selection: comparison.mode == .glyph
        ? items.firstIndex(where: { $0.id == comparison.selectedScalars }) : nil,
      navigate: navigate
    ) {
      HStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          Button {
            select(item.difference.glyph)
          } label: {
            ZStack(alignment: .topLeading) {
              GlyphDifferencePreview(
                glyph: item.difference.glyph, a: comparison.a, b: comparison.b!,
                spacingOnly: comparison.spacing && !comparison.shape, index: true
              ).frame(width: 44, height: 56).allowsHitTesting(false).accessibilityHidden(true)
              Rectangle().fill(WorkbenchStyle.hairline).frame(width: 44, height: 1).offset(y: 54)
              if comparison.frequency {
                Rectangle().fill(WorkbenchStyle.track)
                  .frame(width: maximum > 0 ? 44 * item.measured / maximum : 0, height: 2).offset(
                    y: 53)
              }
              Rectangle().fill(WorkbenchStyle.ink)
                .frame(width: maximum > 0 ? 44 * item.weighted / maximum : 0, height: 2).offset(
                  y: 53)
              if comparison.mode == .glyph && comparison.selectedScalars == item.id {
                Rectangle().fill(WorkbenchStyle.ink).frame(width: 48, height: 2).offset(y: 75)
              }
            }.frame(width: 48, height: 76).contentShape(Rectangle())
          }.buttonStyle(.plain).focusable(false).id(item.id)
            .accessibilityLabel("Inspect \(unicodeDescription(item.difference.glyph))")
            .accessibilityValue("\(index + 1) of \(items.count)")
            .accessibilityAddTraits(
              comparison.mode == .glyph && comparison.selectedScalars == item.id
                ? .isSelected : []
            )
            .help(help(item.difference))
        }
      }
    }
    .mask {
      HStack(spacing: 0) {
        Color.black
        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
          .frame(width: 72)
      }
    }
  }

  private func binding(_ key: WritableKeyPath<Comparison, Bool>) -> Binding<Bool> {
    Binding(
      get: { comparison[keyPath: key] },
      set: { value in model.updatePresentation { $0[keyPath: key] = value } })
  }

  private func help(_ item: GlyphDifference) -> String {
    let frequency =
      item.frequency.map { String(format: "Frequency %.2g%%", $0 * 100) }
      ?? String(format: "Frequency below %.2g%%", CharacterFrequency.floor * 100)
    return unicodeDescription(item.glyph).replacingOccurrences(of: " · ", with: "\n")
      + String(format: "\nShape %.1f%%\nSpacing %.3f em\n", item.shape * 100, item.spacing)
      + frequency + (comparison.frequency ? String(format: " · weight %.2f", item.weight) : "")
  }
}
