import AppKit
import Combine
import TypefaceCore

@MainActor
final class WorkbenchModel: ObservableObject {
  // All windows use the same immutable installed-font snapshot. Swift's once-only
  // initialization lets launch preparation and the first window safely meet here.
  nonisolated static let installedCatalog = FontCatalog()

  @Published var comparison: Comparison {
    didSet { FuzzDiagnostics.shared.snapshot(window: fuzzWindow, comparison: comparison) }
  }
  let catalog: FontCatalog
  private let fuzzWindow: UUID
  let familySimilarity = FamilySimilarityModel()
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
    FuzzDiagnostics.shared.snapshot(window: fuzzWindow, comparison: comparison)
  }

  func edit(_ name: String, undoManager: UndoManager?, _ body: (inout Comparison) -> Void) {
    let previous = comparison
    var next = previous
    body(&next)
    guard previous != next else { return }
    if name == "Change typography" {
      FuzzDiagnostics.shared.validateTypographyEdit(previous: previous, next: next)
    }
    comparison = next
    if continuousEdit == nil { registerUndo(previous, name: name, undoManager: undoManager) }
  }

  func beginContinuousEdit(_ name: String) {
    if continuousEdit == nil { continuousEdit = (name, comparison) }
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

@MainActor
final class RankingModel: ObservableObject {
  @Published var scores: [GlyphDifference] = []
  @Published var comparing = false
  private let engine = DifferenceEngine()

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
    do {
      try await Task.sleep(for: .milliseconds(120))
      #if TYPEFACEOFF_STARTUP_BENCHMARK
        StartupDiagnostics.mark("rankingSearchStarted")
      #endif
      let result = try await engine.scores(a: comparison.a, b: b, sample: comparison.text)
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
