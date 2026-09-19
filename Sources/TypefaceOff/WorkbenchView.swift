import SwiftUI
import TypefaceCore

struct WorkbenchView: View {
  @ObservedObject var document: WorkbenchDocument
  @StateObject private var ranking = RankingModel()
  @StateObject private var scrollPosition = SpecimenScrollPosition()
  @Environment(\.undoManager) private var undoManager
  @Environment(\.locale) private var locale
  @State private var showA = true
  @State private var showB = true
  @State private var showMatch = false
  @State private var showEditor = false
  @State private var customText = ""
  @State private var sharedSize = "22"
  @State private var glyphFocusRequest = UUID()

  private var comparison: Comparison { document.comparison }
  private var rankingKey: RankingKey {
    .init(a: comparison.a, b: comparison.b, text: comparison.text)
  }
  private var ranked: [GlyphDifference] {
    Differences.ranked(ranking.scores, shape: comparison.shape, spacing: comparison.spacing)
  }
  private var highlights: Set<String> {
    Differences.highlights(
      ranking.scores, text: comparison.text, shape: comparison.shape, spacing: comparison.spacing)
  }
  private var highlightKinds: [String: String] {
    var result: [String: String] = [:]
    for (enabled, shape, title) in [
      (comparison.shape, true, "Shape"), (comparison.spacing, false, "Spacing"),
    ]
    where enabled {
      for glyph in Differences.highlights(
        ranking.scores, text: comparison.text, shape: shape, spacing: !shape)
      {
        result[glyph] = result[glyph].map { "\($0) + \(title)" } ?? title
      }
    }
    return result
  }

  var body: some View {
    HStack(spacing: 0) {
      if showA {
        FontInspector(document: document, side: .a).frame(width: 246)
        Divider()
      }
      VStack(spacing: 0) {
        controls
        Divider()
        if comparison.mode == .text {
          HStack(spacing: 0) {
            specimen(comparison.a, side: .a)
            if let b = comparison.b {
              Divider()
              specimen(b, side: .b)
            }
          }
          .background(.white)
          .environment(\.colorScheme, .light)
        } else {
          GlyphComparisonView(
            comparison: comparison, focusRequest: glyphFocusRequest, select: selectGlyph,
            navigate: navigate)
        }
        if comparison.b != nil {
          Divider()
          differences
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      if showB {
        Divider()
        FontInspector(document: document, side: .b).frame(width: 246)
      }
    }
    .background(WorkbenchStyle.panel)
    .tint(WorkbenchStyle.accent)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button("Toggle font A inspector", systemImage: "sidebar.left") { showA.toggle() }
          .help("Show or hide the font A inspector")
      }
      ToolbarItem(placement: .principal) { Text("Typeface/Off").font(.headline) }
      ToolbarItem(placement: .primaryAction) {
        Button("Toggle font B inspector", systemImage: "sidebar.right") { showB.toggle() }
          .help("Show or hide the font B inspector")
      }
    }
    .task(id: rankingKey) { await ranking.update(comparison) }
    .onChange(of: comparison.a.size, initial: true) { syncSize() }
    .onChange(of: comparison.b?.size) { syncSize() }
    .onChange(of: locale) { syncSize() }
    .onChange(of: comparison.sample) { scrollPosition.reset() }
    .onChange(of: comparison.customText) {
      if comparison.sample == .custom { scrollPosition.reset() }
    }
    .sheet(isPresented: $showMatch) { MatchSheet(document: document) }
    .sheet(isPresented: $showEditor) { editor }
  }

  private var controls: some View {
    VStack(spacing: 12) {
      HStack {
        Picker("Comparison mode", selection: presentation(\.mode)) {
          Text("Text").tag(ComparisonMode.text)
          Text("Glyph").tag(ComparisonMode.glyph)
        }.pickerStyle(.segmented).frame(width: 168).labelsHidden()
        Spacer()
        Button("Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
          .labelStyle(.iconOnly).disabled(undoManager?.canUndo != true).help("Undo the last change")
        Button("Match…", systemImage: "slider.horizontal.3") { showMatch = true }
          .disabled(
            !FontRenderer.isAvailable(comparison.a)
              || comparison.b.map { !FontRenderer.isAvailable($0) } != false
          )
          .help("Preview matching weight, x-height, and tracking for two installed fonts")
      }
      HStack(spacing: 12) {
        Picker(
          "Sample",
          selection: Binding(
            get: { comparison.sample },
            set: { sample in
              if sample == .custom {
                openEditor()
              } else {
                edit("Change sample") { $0.sample = sample }
              }
            })
        ) {
          ForEach(Sample.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
        }.labelsHidden().frame(maxWidth: 245)
        Button("Edit text", action: openEditor).buttonStyle(.plain)
        Spacer(minLength: 4)
        TextField(
          comparison.b != nil && comparison.a.size != comparison.b?.size ? "Mixed" : "Size",
          text: $sharedSize
        )
        .frame(width: 48).multilineTextAlignment(.trailing)
        .onSubmit {
          if let value = SharedSizeFormat.parse(sharedSize, locale: locale) {
            edit("Set both sizes") {
              $0.a.set(.size, to: value, catalog: document.catalog)
              $0.b?.set(.size, to: value, catalog: document.catalog)
              $0.calibrate()
            }
          }
          syncSize()
        }
        .accessibilityLabel("Shared point size")
        Text("pt").foregroundStyle(.secondary)
        Button("Swap fonts", systemImage: "arrow.left.arrow.right") {
          edit("Swap fonts") { $0.swap() }
        }
        .labelStyle(.iconOnly).disabled(comparison.b == nil)
      }
    }.padding(16).background(WorkbenchStyle.toolbar)
  }

  private func specimen(_ config: FontConfiguration, side: Side) -> some View {
    SpecimenText(
      config: config, text: comparison.text, sample: comparison.sample, highlights: highlights,
      highlightKinds: highlightKinds,
      side: side, scrollPosition: scrollPosition, select: selectGlyph
    ).frame(maxWidth: .infinity, maxHeight: .infinity).environment(\.colorScheme, .light)
  }

  private var differences: some View {
    let ranked = ranked
    let maximumShape = ranked.map(\.shape).max() ?? 1
    let maximumSpacing = ranked.map(\.spacing).max() ?? 1
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Differences").font(.headline)
        if ranking.comparing {
          ProgressView().controlSize(.small).accessibilityLabel("Comparing glyphs")
        }
        Spacer()
        Toggle("Shape", isOn: presentation(\.shape)).toggleStyle(.checkbox)
        Toggle("Spacing", isOn: presentation(\.spacing)).toggleStyle(
          .checkbox)
      }
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          LazyHStack(spacing: 8) {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, item in
              Button {
                selectGlyph(item.glyph)
              } label: {
                VStack(spacing: 5) {
                  Text(verbatim: item.glyph).font(Font(FontRenderer.font(comparison.a, size: 30)))
                    .frame(height: 38)
                  if comparison.shape || !comparison.spacing {
                    differenceBar(
                      item.shape, maximum: maximumShape,
                      color: Color(red: 0.78, green: 0.68, blue: 0.49))
                  }
                  if comparison.spacing || !comparison.shape {
                    differenceBar(
                      item.spacing, maximum: maximumSpacing, color: .blue)
                  }
                }
                .frame(width: 54, height: 65)
                .background(
                  comparison.mode == .glyph && comparison.selectedGlyph == item.glyph
                    ? Color.white.opacity(0.18) : Color.white.opacity(0.06)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                  RoundedRectangle(cornerRadius: 5).stroke(
                    comparison.mode == .glyph && comparison.selectedGlyph == item.glyph
                      ? Color.yellow.opacity(0.7) : Color.gray.opacity(0.5)))
              }.buttonStyle(.plain).id(item.glyph)
                .accessibilityLabel("Inspect \(unicodeDescription(item.glyph))")
                .help(
                  "\(unicodeDescription(item.glyph)) · #\(index + 1) · "
                    + String(
                      format: "Shape %.1f%% · Spacing %.3f em", item.shape * 100, item.spacing))
            }
          }.padding(1)
        }.scrollIndicators(.hidden).frame(height: 84)
          .onChange(of: comparison.selectedGlyph) { _, glyph in
            proxy.scrollTo(glyph, anchor: .center)
          }
      }
      if ranked.isEmpty && !ranking.comparing {
        Text("No shared characters to compare.").foregroundStyle(.secondary)
      }
    }.padding(16)
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Sample text").font(.title2)
      TextEditor(text: $customText).font(.body).frame(width: 600, height: 320)
        .accessibilityLabel("Custom specimen text")
      HStack {
        Spacer()
        Button("Cancel") { showEditor = false }.keyboardShortcut(.cancelAction)
        Button("Apply") {
          edit("Edit sample") {
            $0.customText = customText
            $0.sample = .custom
          }
          scrollPosition.reset()
          showEditor = false
        }.keyboardShortcut(.defaultAction)
      }
    }.padding(24)
  }

  private func openEditor() {
    customText = comparison.text
    showEditor = true
  }

  private func differenceBar(_ value: Double, maximum: Double, color: Color) -> some View {
    Capsule().fill(.white.opacity(0.12)).frame(width: 32, height: 2)
      .overlay(alignment: .leading) {
        Capsule().fill(color).frame(width: maximum > 0 ? 32 * value / maximum : 0, height: 2)
      }.accessibilityHidden(true)
  }

  private func edit(_ name: String, _ body: (inout Comparison) -> Void) {
    document.edit(name, undoManager: undoManager, body)
  }
  private func presentation<Value>(_ key: WritableKeyPath<Comparison, Value>) -> Binding<
    Value
  > {
    Binding(
      get: { document.comparison[keyPath: key] },
      set: { value in
        document.updatePresentation { $0[keyPath: key] = value }
        if comparison.mode == .glyph { glyphFocusRequest = UUID() }
      })
  }
  private func syncSize() {
    sharedSize =
      comparison.b != nil && comparison.a.size != comparison.b?.size
      ? "" : SharedSizeFormat.style(locale: locale).format(comparison.a.size)
  }
  private func selectGlyph(_ glyph: String) {
    guard let first = glyph.first else { return }
    document.updatePresentation {
      $0.selectedGlyph = String(first)
      $0.mode = .glyph
    }
    glyphFocusRequest = UUID()
  }
  private func navigate(_ direction: Int) {
    let glyphs =
      ranked.isEmpty ? Differences.candidates(sample: comparison.text) : ranked.map(\.glyph)
    guard !glyphs.isEmpty else { return }
    let index = glyphs.firstIndex(of: comparison.selectedGlyph) ?? 0
    selectGlyph(glyphs[(index + direction + glyphs.count) % glyphs.count])
  }
}

enum SharedSizeFormat {
  static func style(locale: Locale) -> FloatingPointFormatStyle<Double> {
    .number.precision(.fractionLength(0...3)).grouping(.never).locale(locale)
  }

  static func parse(_ text: String, locale: Locale) -> Double? {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.isLenient = false
    formatter.usesGroupingSeparator = false
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var range = NSRange(location: 0, length: text.utf16.count)
    var result: AnyObject?
    do { try formatter.getObjectValue(&result, for: text, range: &range) } catch { return nil }
    guard range.length == text.utf16.count, let value = (result as? NSNumber)?.doubleValue,
      value.isFinite
    else { return nil }
    return value
  }
}

private struct RankingKey: Equatable {
  let a: FontConfiguration
  let b: FontConfiguration?
  let text: String
}

func number(_ value: Double, digits: Int = 1) -> String {
  value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
}
