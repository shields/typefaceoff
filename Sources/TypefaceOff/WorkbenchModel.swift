import AppKit
import Combine
import TypefaceCore

@MainActor
final class WorkbenchModel: ObservableObject {
  // All windows use the same immutable installed-font snapshot. Swift's once-only
  // initialization lets launch preparation and the first window safely meet here.
  nonisolated static let installedCatalog = FontCatalog()

  @Published var comparison: Comparison {
    didSet {
      // Canonically equivalent text can contain different ranking candidates.
      if !comparison.text.utf8.elementsEqual(oldValue.text.utf8) {
        specimenGlyphs = Set(comparison.text.map { Array($0.unicodeScalars) })
      }
      FuzzDiagnostics.shared.snapshot(window: fuzzWindow, comparison: comparison)
    }
  }
  private(set) var specimenGlyphs: Set<[Unicode.Scalar]>
  let catalog: FontCatalog
  let initialWork: InitialFontWork
  private let fuzzWindow: UUID
  let familySimilarity = FamilySimilarityModel()
  let languages = LanguageBrowserModel()
  private var continuousEdit: (name: String, initial: Comparison)?

  init(comparison: Comparison = Comparison()) {
    #if TYPEFACEOFF_STARTUP_BENCHMARK
      StartupDiagnostics.mark("catalogStart")
    #endif
    catalog = Self.installedCatalog
    #if TYPEFACEOFF_STARTUP_BENCHMARK
      StartupDiagnostics.mark("catalogReady")
    #endif
    fuzzWindow = UUID()
    self.comparison = comparison
    specimenGlyphs = Set(comparison.text.map { Array($0.unicodeScalars) })
    initialWork = InitialFontWork(comparison: comparison)
    FuzzDiagnostics.shared.snapshot(window: fuzzWindow, comparison: comparison)
  }

  deinit { initialWork.cancel() }

  func edit(_ name: String, undoManager: UndoManager?, _ body: (inout Comparison) -> Void) {
    let previous = comparison
    var next = previous
    body(&next)
    guard previous != next || !previous.customText.utf8.elementsEqual(next.customText.utf8) else {
      return
    }
    if name == "Change typography" {
      FuzzDiagnostics.shared.validateTypographyEdit(previous: previous, next: next)
    }
    comparison = next
    if continuousEdit == nil { registerUndo(previous, name: name, undoManager: undoManager) }
  }

  func beginContinuousEdit(_ name: String) {
    if continuousEdit == nil { continuousEdit = (name, comparison) }
  }

  func useLanguageSpecimen(_ text: String, undoManager: UndoManager?) {
    edit("Use language specimen", undoManager: undoManager) {
      $0.customText = text
      $0.sample = .custom
    }
    updatePresentation { $0.mode = .text }
  }

  /// Browsing changes do not consume Undo steps.
  func updatePresentation(_ body: (inout Comparison) -> Void) {
    var next = comparison
    body(&next)
    if next != comparison { comparison = next }
  }

  func endContinuousEdit(undoManager: UndoManager?) {
    guard let edit = continuousEdit else { return }
    continuousEdit = nil
    if edit.initial != comparison {
      registerUndo(edit.initial, name: edit.name, undoManager: undoManager)
    }
  }

  private func registerUndo(_ previous: Comparison, name: String, undoManager: UndoManager?) {
    undoManager?.registerUndo(withTarget: self) { [weak undoManager] target in
      MainActor.assumeIsolated {
        target.edit(name, undoManager: undoManager) { current in
          var restored = previous
          // Keep the user's current inspection while undoing a font or sample edit.
          restored.mode = current.mode
          restored.selectedGlyph = current.selectedGlyph
          restored.shape = current.shape
          restored.spacing = current.spacing
          restored.frequency = current.frequency
          current = restored
        }
      }
    }
    undoManager?.setActionName(name)
  }
}

/// The inputs of a difference ranking. Edits outside them keep the current scores.
struct RankingKey: Equatable {
  let input: DifferenceInput?
  let text: String

  init(_ comparison: Comparison) {
    input = comparison.b.map { DifferenceInput(a: comparison.a, b: $0) }
    text = comparison.text
  }

  // String equality is canonical equivalence, which would keep the scores of a sample whose
  // characters were replaced by canonically equivalent but distinct scalars.
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.input == rhs.input && lhs.text.unicodeScalars.elementsEqual(rhs.text.unicodeScalars)
  }
}

@MainActor
final class RankingModel: ObservableObject {
  @Published var scores: [GlyphDifference] = []
  @Published var comparing = false
  private let engine: DifferenceEngine
  private var preparation: PreparedSearch<Comparison, [GlyphDifference]>?
  private var hasRequested = false

  init(preparation: InitialFontWork? = nil) {
    engine = preparation?.rankingEngine ?? DifferenceEngine()
    self.preparation = preparation?.ranking
  }

  func update(_ comparison: Comparison) async {
    #if TYPEFACEOFF_STARTUP_BENCHMARK
      StartupDiagnostics.mark("rankingRequested")
    #endif
    let fuzzWork = FuzzDiagnostics.shared.beginWork("ranking")
    defer {
      FuzzDiagnostics.shared.endWork(
        fuzzWork, kind: "ranking", outcome: Task.isCancelled ? "cancelled" : "completed")
    }
    scores = []
    guard let b = comparison.b else {
      comparing = false
      return
    }
    comparing = true
    let debounce = hasRequested
    hasRequested = true
    let prepared = preparation
    preparation = nil
    do {
      // Start the initial computation while the window is still laying out.
      // Subsequent requests debounce rapid font and appearance edits.
      if debounce { try await Task.sleep(for: .milliseconds(120)) }
      try Task.checkCancellation()
      #if TYPEFACEOFF_STARTUP_BENCHMARK
        StartupDiagnostics.mark("rankingLoadStarted")
      #endif
      let result: [GlyphDifference]
      // Ranking identities distinguish scalars that String equality treats as equivalent.
      if let prepared,
        prepared.input.customText.unicodeScalars.elementsEqual(
          comparison.customText.unicodeScalars),
        let ready = try await prepared.value(for: comparison)
      {
        result = ready
      } else {
        result = try await engine.scores(a: comparison.a, b: b, sample: comparison.text)
      }
      try Task.checkCancellation()
      scores = result
      comparing = false
      #if TYPEFACEOFF_STARTUP_BENCHMARK
        StartupDiagnostics.mark("rankingReady")
      #endif
    } catch {
      // A newer request owns the progress indicator after cancellation.
      if !Task.isCancelled { comparing = false }
    }
  }
}
