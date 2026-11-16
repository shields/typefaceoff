import SwiftUI
import TypefaceCore

struct WorkbenchView: View {
  @ObservedObject var model: WorkbenchModel
  @StateObject private var ranking: RankingModel
  @StateObject private var scrollPosition = SpecimenScrollPosition()
  @Environment(\.workbenchUndoManager) private var undoManager
  @State private var searchFocused = false
  @State private var showInspector: Bool
  @State private var familyFocus: Side?
  @State private var glyphZoom: Double
  @State private var showMatch: Bool
  @State private var showEditor: Bool
  @State private var customText: String
  @State private var glyphFocusRequest: UUID
  @State private var glyphFocused: Bool
  @State private var searchingCharacters: Bool

  // Initialize state explicitly so Xcode 26's coverage does not include unused
  // synthesized initializers for the property defaults.
  init(model: WorkbenchModel) {
    self.model = model
    _ranking = StateObject(wrappedValue: RankingModel(preparation: model.initialWork))
    _showInspector = State(initialValue: false)
    _familyFocus = State(initialValue: nil)
    _glyphZoom = State(initialValue: 1)
    _showMatch = State(initialValue: false)
    _showEditor = State(initialValue: false)
    _customText = State(initialValue: "")
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
      inspector: $showInspector, mode: presentation(\.mode),
      shape: presentation(\.shape), spacing: presentation(\.spacing),
      frequency: presentation(\.frequency), zoom: $glyphZoom,
      find: { searchFocused = true }, focusFont: { familyFocus = $0 }, navigate: navigate,
      match: openMatch, editText: openEditor)
  }
  private var rankingKey: RankingKey { .init(comparison) }
  private var ranked: [GlyphDifference] {
    Differences.ranked(
      ranking.scores, shape: comparison.shape, spacing: comparison.spacing,
      frequency: comparison.frequency)
  }
  private var highlights: Set<String> {
    Differences.highlights(
      ranking.scores, present: model.specimenGlyphs, shape: comparison.shape,
      spacing: comparison.spacing,
      frequency: comparison.frequency)
  }
  private var highlightKinds: [String: String] {
    var result: [String: String] = [:]
    for (enabled, shape, title) in [
      (comparison.shape, true, "Shape"), (comparison.spacing, false, "Spacing"),
    ]
    where enabled {
      for glyph in Differences.highlights(
        ranking.scores, present: model.specimenGlyphs, shape: shape, spacing: !shape,
        frequency: comparison.frequency)
      {
        result[glyph] = result[glyph].map { "\($0) + \(title)" } ?? title
      }
    }
    return result
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        SpecificationHeader(
          model: model, inspectorOpen: showInspector, matching: showMatch,
          familyFocus: $familyFocus,
          openInspector: { section in
            model.inspector.reveal(section)
            showInspector = true
          }, match: openMatch)
        if comparison.mode != .languages {
          DifferenceIndex(
            model: model, ranking: ranking, inspectorOpen: showInspector,
            select: selectGlyph, navigate: navigate)
        }
        switch comparison.mode {
        case .text:
          TextComparisonView(
            comparison: comparison, highlights: highlights, highlightKinds: highlightKinds,
            scrollPosition: scrollPosition, select: selectGlyph)
        case .glyph:
          GlyphComparisonView(
            comparison: comparison, focusRequest: glyphFocusRequest, searching: characterSearch,
            select: selectGlyph, navigate: navigate,
            showText: { model.updatePresentation { $0.mode = .text } },
            focusChanged: { glyphFocused = $0 }, zoom: $glyphZoom)
        case .languages:
          LanguageBrowserView(
            browser: model.languages, comparison: comparison, inspect: selectGlyph,
            useSpecimen: { model.useLanguageSpecimen($0, undoManager: undoManager) })
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(WorkbenchStyle.paper)
      .inspector(isPresented: $showInspector) {
        // Defer content creation until the inspector can honor its initial scroll position.
        if showInspector {
          ComparisonInspector(model: model, state: model.inspector)
            .inspectorColumnWidth(320)
        }
      }
      // Native inspector animations can overwrite a newer visibility request when they finish.
      .transaction(value: showInspector) { $0.disablesAnimations = true }
      .navigationTitle(windowTitle)
      .toolbar {
        ToolbarItem(placement: .navigation) {
          Menu(comparison.sample.title) {
            ForEach(
              Sample.allCases.filter { $0 != .custom || !comparison.customText.isEmpty }, id: \.self
            ) { sample in
              Button(sample.title) { edit("Change sample") { $0.sample = sample } }
            }
            Divider()
            Button("Edit Text…", action: openEditor)
          }.accessibilityIdentifier("Sample selector")
        }
        ToolbarItem(placement: .principal) {
          WorkbenchModePicker(mode: presentation(\.mode)).frame(width: 260)
        }
        ToolbarItem(placement: .primaryAction) {
          ToolbarSearch(
            comparison: comparison, languages: model.languages, focus: $searchFocused,
            choose: selectGlyph
          ).frame(width: 200)
        }
        ToolbarItem(placement: .primaryAction) {
          Button("Show Inspector", systemImage: "sidebar.right") { showInspector.toggle() }
            .accessibilityIdentifier("Toggle comparison inspector")
            .help("Show or hide the comparison inspector (Control-Command-I)")
        }
      }
      .toolbar(removing: .title)
    }
    .frame(minWidth: showInspector ? 1280 : 960, minHeight: 600)
    .containerBackground(WorkbenchStyle.paper, for: .window)
    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    .preferredColorScheme(.light)
    .tint(WorkbenchStyle.ink)
    .focusedSceneValue(\.workbenchActions, showMatch || showEditor ? nil : commands)
    .task(id: rankingKey) { await ranking.update(comparison) }
    .task(id: comparison.mode == .languages ? LanguageBrowserModel.Request(comparison) : nil) {
      if comparison.mode == .languages { await model.languages.update(.init(comparison)) }
    }
    .onChange(of: comparison.sample) { scrollPosition.reset() }
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
    selectGlyph(comparison.neighbour(in: glyphs, direction: direction)!)
  }
}

enum SharedSizeFormat {
  static func style(locale: Locale) -> FloatingPointFormatStyle<Double> {
    .number.precision(.fractionLength(0...3)).grouping(.never).locale(locale)
  }

  static func parse(_ text: String, locale: Locale) -> Double? {
    SpecificationNumber.parse(text, locale: locale)
  }
}

func number(_ value: Double, digits: Int = 1) -> String {
  value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
}
