import AppKit
import SwiftUI
import TypefaceCore

struct GlyphComparisonView: View {
  let comparison: Comparison
  let focusRequest: UUID
  @Binding var searching: Bool
  let select: (String) -> Void
  let navigate: (Int) -> Void
  let showText: () -> Void
  let focusChanged: (Bool) -> Void
  @Binding private var zoom: Double
  @State private var appeared: Bool
  @Environment(\.locale) private var locale

  init(
    comparison: Comparison, focusRequest: UUID, searching: Binding<Bool>,
    select: @escaping (String) -> Void, navigate: @escaping (Int) -> Void,
    showText: @escaping () -> Void, focusChanged: @escaping (Bool) -> Void,
    zoom: Binding<Double> = .constant(1)
  ) {
    self.comparison = comparison
    self.focusRequest = focusRequest
    _searching = searching
    self.select = select
    self.navigate = navigate
    self.showText = showText
    self.focusChanged = focusChanged
    _zoom = zoom
    _appeared = State(initialValue: false)
  }

  var body: some View {
    GeometryReader { geometry in
      let layout = GlyphRendering.layout(
        comparison, width: geometry.size.width, height: geometry.size.height)
      ZStack(alignment: .topLeading) {
        GlyphSolos(comparison: comparison, layout: layout)
          .frame(width: layout.stageX, height: geometry.size.height)
        GlyphCanvas(
          comparison: comparison, focusRequest: focusRequest, navigate: navigate,
          showText: showText,
          focusChanged: focusChanged, zoom: $zoom
        ).frame(width: layout.stageWidth, height: geometry.size.height).offset(x: layout.stageX)
        searchButton.frame(width: layout.stageX - 128, alignment: .leading).offset(x: 64, y: 11)
        metrics(layout).offset(y: layout.baseline + 66)
        HStack(spacing: 12) {
          caption
          Spacer(minLength: 0)
          zoomControls
        }.frame(width: layout.stageWidth - 24, height: 24)
          .offset(x: layout.stageX, y: layout.baseline + 117)
      }
    }.background(WorkbenchStyle.paper).foregroundStyle(WorkbenchStyle.ink)
      .environment(\.colorScheme, .light).task { appeared = true }
  }

  private var searchButton: some View {
    let description = unicodeDescription(comparison.selectedGlyph)
    let code = comparison.selectedScalars.map { String(format: "U+%04X", $0.value) }.joined(
      separator: " · ")
    let name = comparison.selectedScalars.map { $0.properties.name ?? "UNNAMED CHARACTER" }.joined(
      separator: " · ")
    return Button {
      searching = true
    } label: {
      VStack(alignment: .leading, spacing: 9) {
        Text(verbatim: code).font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
          .lineLimit(1).truncationMode(.middle)
        (Text(verbatim: name) + Text(" ") + Text(Image(systemName: "magnifyingglass")))
          .font(.system(size: 20)).lineSpacing(1).lineLimit(2).multilineTextAlignment(.leading)
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel("Search characters")
      .accessibilityValue(Text(verbatim: description))
      .help("\(description)\nFind a character by name, code point, or the character itself (⌘F)")
      .popover(
        isPresented: Binding(get: { searching && appeared }, set: { searching = $0 }),
        arrowEdge: .bottom
      ) {
        CharacterSearchPicker(comparison: comparison) { glyph in
          searching = false
          select(glyph)
        }
      }
  }

  private var zoomControls: some View {
    HStack(spacing: 4) {
      Button {
        zoom = max(1, zoom / 1.25)
      } label: {
        Image(systemName: "minus").frame(width: 24, height: 24).contentShape(Rectangle())
      }.accessibilityLabel("Zoom out").disabled(zoom <= 1)
      Button {
        zoom = 1
      } label: {
        Text(verbatim: "\(Int((zoom * 100).rounded()))%")
          .monospacedDigit().frame(width: 44, height: 24).contentShape(Rectangle())
      }.accessibilityLabel("Reset glyph zoom").help("Reset the overlay's zoom and pan to 100%")
      Button {
        zoom = min(8, zoom * 1.25)
      } label: {
        Image(systemName: "plus").frame(width: 24, height: 24).contentShape(Rectangle())
      }.accessibilityLabel("Zoom in").disabled(zoom >= 8)
    }.font(.system(size: 13)).buttonStyle(.plain)
  }

  @ViewBuilder private var caption: some View {
    let installedA = FontRenderer.isAvailable(comparison.a)
    let installedB = comparison.b.map { FontRenderer.isAvailable($0) } != false
    let a = FontRenderer.supports(comparison.selectedGlyph, config: comparison.a)
    let b = comparison.b.map { FontRenderer.supports(comparison.selectedGlyph, config: $0) } == true
    if !installedA || !installedB {
      Text("\(!installedA ? "A" : "B") is not installed. Choose an installed font above.")
        .font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
    } else if comparison.b != nil && a && b {
      (Text("A over B").fontWeight(.semibold)
        + Text(
          comparison.spacing && !comparison.shape
            ? "  Spacing alone aligns advance origins" : "  Shape aligns left ink edges"
        )
        .foregroundColor(WorkbenchStyle.secondaryInk)).font(.system(size: 11))
    } else if comparison.b != nil && a != b {
      let missing = a ? "B" : "A"
      let present = a ? "A" : "B"
      (Text("Character unavailable in \(missing)").fontWeight(.semibold)
        + Text("  \(present)’s ink alone").foregroundColor(WorkbenchStyle.secondaryInk))
        .font(.system(size: 11))
    } else if !a && !b {
      Text("Character unavailable").font(.system(size: 11)).foregroundStyle(
        WorkbenchStyle.secondaryInk)
    }
  }

  private func metrics(_ layout: GlyphLayout) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(["Advance", "LSB", "RSB", "x-height", "Units/em"].enumerated()), id: \.offset) {
        index, title in
        Text(verbatim: title).font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
          .offset(x: 64, y: index < 3 ? Double(22 + index * 20) : Double(28 + index * 20))
      }
      Rectangle().fill(WorkbenchStyle.hairline).frame(
        width: (comparison.b == nil ? layout.columnA : layout.columnB) + layout.columnWidth - 64,
        height: 1
      ).offset(x: 64, y: 85)
      metricColumn(.a, width: layout.columnWidth).offset(x: layout.columnA)
      if comparison.b != nil {
        metricColumn(.b, width: layout.columnWidth).offset(x: layout.columnB)
      }
    }.frame(height: 130, alignment: .topLeading)
  }

  private func metricColumn(_ side: Side, width: Double) -> some View {
    let config = comparison[side]!
    let installed = FontRenderer.isAvailable(config)
    let supported = FontRenderer.supports(comparison.selectedGlyph, config: config)
    let metric =
      supported ? FontRenderer.nativeMetrics(comparison.selectedGlyph, config: config) : nil
    let xHeight = installed ? FontRenderer.xHeight(config: config) : nil
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text(side == .a ? "A" : "B").font(.system(size: 13, weight: .bold))
          .foregroundStyle(
            installed
              ? Color(nsColor: side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue)
              : WorkbenchStyle.secondaryInk)
        Text(verbatim: installed ? config.face.family : config.postScriptName)
          .font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk).lineLimit(1)
      }.frame(height: 16, alignment: .top).padding(.bottom, 6)
      metricValue(metric?.advance, em: config.face.unitsPerEm, width: width)
      metricValue(metric?.leftBearing, em: config.face.unitsPerEm, width: width)
      metricValue(metric?.rightBearing, em: config.face.unitsPerEm, width: width)
      Color.clear.frame(height: 6)
      metricValue(xHeight, em: config.face.unitsPerEm, width: width)
      HStack {
        (Text(verbatim: installed ? String(config.face.unitsPerEm) : "—")
          + Text(installed ? " u" : "").foregroundColor(.clear))
          .accessibilityLabel(installed ? String(config.face.unitsPerEm) : "Unavailable")
          .frame(width: width * 0.45, alignment: .trailing)
        Spacer(minLength: 0)
      }.frame(height: 20)
    }.frame(width: width).font(.system(size: 13)).monospacedDigit()
  }

  private func metricValue(_ value: Double?, em: Int, width: Double) -> some View {
    HStack(spacing: 0) {
      if let value {
        (Text(verbatim: number(value, digits: 0))
          + Text(" u").foregroundColor(WorkbenchStyle.secondaryInk))
          .frame(width: width * 0.45, alignment: .trailing)
        (Text(
          verbatim: SpecificationNumber.format(value / Double(em), precision: 3, locale: locale))
          + Text(" em").foregroundColor(WorkbenchStyle.secondaryInk))
          .frame(width: width * 0.55, alignment: .trailing)
      } else {
        Text("—").foregroundStyle(WorkbenchStyle.secondaryInk)
          .frame(width: width * 0.45, alignment: .trailing)
        Spacer(minLength: 0)
      }
    }.frame(height: 20)
  }
}

struct GlyphCanvas: NSViewRepresentable {
  let comparison: Comparison
  let focusRequest: UUID
  let navigate: (Int) -> Void
  let showText: () -> Void
  let focusChanged: (Bool) -> Void
  @Binding var zoom: Double
  func makeNSView(context: Context) -> GlyphScrollView { GlyphScrollView() }
  func updateNSView(_ scroll: GlyphScrollView, context: Context) {
    let view = scroll.canvas
    view.navigate = navigate
    view.showText = showText
    view.focusChanged = focusChanged
    view.update(comparison)
    view.requestFocus(focusRequest)
    scroll.zoomChanged = { zoom = $0 }
    scroll.setZoom(zoom)
    scroll.annotations.needsDisplay = true
  }
}
