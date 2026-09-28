import SwiftUI
import TypefaceCore

struct WorkbenchView: View {
  @ObservedObject var model: WorkbenchModel
  @StateObject private var ranking: RankingModel
  @StateObject private var scrollPosition = SpecimenScrollPosition()
  @Environment(\.workbenchUndoManager) private var undoManager
  @Environment(\.locale) private var locale
  @Environment(\.appearsActive) private var appearsActive
  @State private var showA: Bool
  @State private var showB: Bool
  @State private var showMatch: Bool
  @State private var showEditor: Bool
  @State private var customText: String
  @State private var sharedSize: String
  @State private var glyphFocusRequest: UUID
  @State private var glyphFocused: Bool
  @State private var searchingCharacters: Bool

  // Initialize state explicitly so Xcode 26's coverage does not include unused
  // synthesized initializers for the property defaults.
  init(model: WorkbenchModel) {
    self.model = model
    _ranking = StateObject(wrappedValue: RankingModel(preparation: model.initialWork))
    _showA = State(initialValue: true)
    _showB = State(initialValue: true)
    _showMatch = State(initialValue: false)
    _showEditor = State(initialValue: false)
    _customText = State(initialValue: "")
    _sharedSize = State(initialValue: "22")
    _glyphFocusRequest = State(initialValue: UUID())
    _glyphFocused = State(initialValue: false)
    _searchingCharacters = State(initialValue: false)
  }

  private var comparison: Comparison { model.comparison }
  private var windowTitle: String {
    [comparison.a, comparison.b].compactMap { $0 }.map { config in
      FontRenderer.isAvailable(config)
        ? config.face.family : "\(config.postScriptName) (unavailable)"
    }.joined(separator: " vs. ")
  }

  private var commands: WorkbenchActions {
    WorkbenchActions(
      model: model, undoManager: undoManager,
      showA: $showA, showB: $showB, mode: presentation(\.mode),
      shape: presentation(\.shape), spacing: presentation(\.spacing),
      frequency: presentation(\.frequency), characterSearch: characterSearch, match: openMatch,
      editText: openEditor)
  }
  private var rankingKey: RankingKey {
    .init(a: comparison.a, b: comparison.b, text: comparison.text)
  }
  private var ranked: [GlyphDifference] {
    Differences.ranked(
      ranking.scores, shape: comparison.shape, spacing: comparison.spacing,
      frequency: comparison.frequency)
  }
  private var highlights: Set<String> {
    Differences.highlights(
      ranking.scores, text: comparison.text, shape: comparison.shape, spacing: comparison.spacing,
      frequency: comparison.frequency)
  }
  private var highlightKinds: [String: String] {
    var result: [String: String] = [:]
    for (enabled, shape, title) in [
      (comparison.shape, true, "Shape"), (comparison.spacing, false, "Spacing"),
    ]
    where enabled {
      for glyph in Differences.highlights(
        ranking.scores, text: comparison.text, shape: shape, spacing: !shape,
        frequency: comparison.frequency)
      {
        result[glyph] = result[glyph].map { "\($0) + \(title)" } ?? title
      }
    }
    return result
  }

  var body: some View {
    HStack(spacing: 0) {
      InspectorPanel(model: model, side: .a, isVisible: showA)
      if showA { Divider() }
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
            comparison: comparison, focusRequest: glyphFocusRequest, searching: characterSearch,
            select: selectGlyph, navigate: navigate,
            showText: { model.updatePresentation { $0.mode = .text } },
            focusChanged: { glyphFocused = $0 })
        }
        if comparison.b != nil {
          Divider()
          differences
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      if showB { Divider() }
      InspectorPanel(model: model, side: .b, isVisible: showB)
    }
    .background(WorkbenchStyle.panel)
    .tint(WorkbenchStyle.accent)
    .navigationTitle(windowTitle)
    .focusedSceneValue(\.workbenchActions, showMatch || showEditor ? nil : commands)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button("Toggle font A inspector", systemImage: "sidebar.left") { showA.toggle() }
          .help("Show or hide the font A inspector")
      }
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
    // The search popover's anchor leaves with the glyph view.
    .onChange(of: comparison.mode) { _, mode in
      if mode != .glyph { searchingCharacters = false }
    }
    .onChange(of: comparison.customText) {
      if comparison.sample == .custom { scrollPosition.reset() }
    }
    .sheet(isPresented: $showMatch) {
      MatchSheet(model: model, fit: FontFitModel(catalog: model.catalog))
    }
    .sheet(isPresented: $showEditor) { editor }
  }

  private var controls: some View {
    VStack(spacing: 12) {
      HStack {
        Picker("Comparison mode", selection: presentation(\.mode).settingAfterViewUpdate) {
          Text("Text").tag(ComparisonMode.text)
          Text("Glyph").tag(ComparisonMode.glyph)
        }.pickerStyle(.segmented).frame(width: 168).labelsHidden()
        Spacer()
        Button("Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
          .labelStyle(.iconOnly).disabled(undoManager?.canUndo != true).help("Undo the last change")
        Button("Match…", systemImage: "slider.horizontal.3", action: openMatch)
          .disabled(!commands.canMatch)
          .help("Preview closer axes, typography, and tracking for font B")
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
              $0.a.set(.size, to: value, catalog: model.catalog)
              $0.b?.set(.size, to: value, catalog: model.catalog)
              $0.calibrate()
            }
          }
          syncSize()
        }
        .accessibilityLabel("Shared point size")
        .accessibilityIdentifier("Shared point size")
        Text("pt").foregroundStyle(.secondary)
        Button("Swap fonts", systemImage: "arrow.left.arrow.right", action: swapFonts)
          .labelStyle(.iconOnly).disabled(comparison.b == nil)
          .help("Swap fonts A and B, including their appearance and typography settings")
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
        Toggle("Frequency", isOn: presentation(\.frequency)).toggleStyle(.checkbox)
          .help(
            "Weight differences by how often each character appears in text worldwide")
      }
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          LazyHStack(spacing: 8) {
            ForEach(ranked) { item in
              Button {
                selectGlyph(item.glyph)
              } label: {
                stripItem(item, maximumShape: maximumShape, maximumSpacing: maximumSpacing)
              }.buttonStyle(.plain).id(item.id)
                .accessibilityLabel("Inspect \(unicodeDescription(item.glyph))")
                .accessibilityAddTraits(isInspected(item.glyph) ? .isSelected : [])
                .help(stripHelp(item))
            }
          }.padding(1)
        }.scrollIndicators(.hidden).frame(height: 84)
          .onChange(of: comparison.selectedScalars) {
            proxy.scrollTo(comparison.selectedScalars, anchor: .center)
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
        .accessibilityIdentifier("Custom specimen text")
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

  private var characterSearch: Binding<Bool> {
    Binding(
      get: { searchingCharacters },
      set: { open in
        if open { model.updatePresentation { $0.mode = .glyph } }
        searchingCharacters = open
      })
  }

  private func openMatch() { showMatch = true }

  private func openEditor() {
    customText = comparison.text
    showEditor = true
  }

  private func swapFonts() {
    commands.swap()
  }

  private func stripItem(_ item: GlyphDifference, maximumShape: Double, maximumSpacing: Double)
    -> some View
  {
    let isSelected = isInspected(item.glyph)
    return VStack(spacing: 5) {
      if let b = comparison.b {
        GlyphDifferencePreview(
          glyph: item.glyph, a: comparison.a, b: b,
          spacingOnly: comparison.spacing && !comparison.shape
        )
        .frame(width: 46, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      if comparison.shape || !comparison.spacing {
        differenceBar(
          item, \.shape, maximum: maximumShape, color: Color(red: 0.78, green: 0.68, blue: 0.49))
      }
      if comparison.spacing || !comparison.shape {
        differenceBar(item, \.spacing, maximum: maximumSpacing, color: .blue)
      }
    }
    .frame(width: 54, height: 65)
    .background(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 5))
    .overlay(
      RoundedRectangle(cornerRadius: 5).stroke(
        isSelected
          ? (appearsActive && glyphFocused ? WorkbenchStyle.accent : Color.white.opacity(0.4))
          : Color.gray.opacity(0.5)))
  }

  private func stripHelp(_ item: GlyphDifference) -> String {
    unicodeDescription(item.glyph).replacingOccurrences(of: " · ", with: "\n") + "\n"
      + String(format: "Shape %.1f%%\nSpacing %.3f em\n", item.shape * 100, item.spacing)
      + frequencyTooltip(item)
  }

  private func differenceBar(
    _ item: GlyphDifference, _ metric: KeyPath<GlyphDifference, Double>, maximum: Double,
    color: Color
  ) -> some View {
    func width(_ length: Double) -> Double { maximum > 0 ? 32 * length / maximum : 0 }
    let value = item[keyPath: metric]
    return Capsule().fill(.white.opacity(0.12)).frame(width: 32, height: 2)
      .overlay(alignment: .leading) {
        if comparison.frequency {
          Capsule().fill(color.opacity(0.35)).frame(width: width(value), height: 2)
        }
      }
      .overlay(alignment: .leading) {
        Capsule().fill(color)
          .frame(width: width(item.weighted(value, frequency: comparison.frequency)), height: 2)
      }.accessibilityHidden(true)
  }

  private func frequencyTooltip(_ item: GlyphDifference) -> String {
    func percent(_ share: Double) -> String { String(format: "%.2g%%", share * 100) }
    let line =
      item.frequency.map { "Frequency \(percent($0))" }
      ?? "Frequency below \(percent(CharacterFrequency.floor))"
    guard comparison.frequency else { return line }
    return line + String(format: " · weight %.2f", item.weight)
  }

  private func edit(_ name: String, _ body: (inout Comparison) -> Void) {
    model.edit(name, undoManager: undoManager, body)
  }
  private func presentation<Value>(_ key: WritableKeyPath<Comparison, Value>) -> Binding<
    Value
  > {
    Binding(
      get: { model.comparison[keyPath: key] },
      set: { value in
        model.updatePresentation { $0[keyPath: key] = value }
        if comparison.mode == .glyph { glyphFocusRequest = UUID() }
      })
  }
  private func syncSize() {
    sharedSize =
      comparison.b != nil && comparison.a.size != comparison.b?.size
      ? "" : SharedSizeFormat.style(locale: locale).format(comparison.a.size)
  }
  private func isInspected(_ glyph: String) -> Bool {
    comparison.mode == .glyph && comparison.matches(glyph)
  }
  private func selectGlyph(_ glyph: String) {
    guard let first = glyph.first else { return }
    model.updatePresentation {
      $0.selectedGlyph = String(first)
      $0.mode = .glyph
    }
    glyphFocusRequest = UUID()
  }
  private func navigate(_ direction: Int) {
    let glyphs =
      ranked.isEmpty ? Differences.candidates(sample: comparison.text) : ranked.map(\.glyph)
    guard !glyphs.isEmpty else { return }
    // A canonically equivalent spelling still navigates from its place in the list.
    let index =
      glyphs.firstIndex { comparison.matches($0) }
      ?? glyphs.firstIndex(of: comparison.selectedGlyph) ?? 0
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
