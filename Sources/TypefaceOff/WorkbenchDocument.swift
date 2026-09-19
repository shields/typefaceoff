import AppKit
import Combine
import SwiftUI
import Synchronization
import TypefaceCore
import UniformTypeIdentifiers

@MainActor
// SwiftUI observes on the main actor; file callbacks use the locked snapshot.
final class WorkbenchDocument: @preconcurrency ReferenceFileDocument {
  nonisolated static var readableContentTypes: [UTType] { [.typefaceComparison] }
  let objectWillChange = ObservableObjectPublisher()
  private let state: Mutex<Comparison>
  @MainActor var comparison: Comparison {
    get { state.withLock { $0 } }
    set {
      objectWillChange.send()
      state.withLock { $0 = newValue }
    }
  }
  let catalog = FontCatalog()
  private var continuousEdit: (name: String, initial: Comparison)?
  nonisolated init(comparison: Comparison = Comparison()) { state = Mutex(comparison) }

  nonisolated required init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    state = Mutex(try Comparison.decode(data))
  }

  nonisolated func snapshot(contentType: UTType) throws -> Comparison { state.withLock { $0 } }

  nonisolated func fileWrapper(snapshot: Comparison, configuration: WriteConfiguration) throws
    -> FileWrapper
  {
    FileWrapper(regularFileWithContents: try snapshot.encoded())
  }

  @MainActor
  func edit(_ name: String, undoManager: UndoManager?, _ body: (inout Comparison) -> Void) {
    let previous = comparison
    var next = previous
    body(&next)
    guard previous != next else { return }
    comparison = next
    if continuousEdit == nil { registerUndo(previous, name: name, undoManager: undoManager) }
  }

  func beginContinuousEdit(_ name: String) {
    if continuousEdit == nil { continuousEdit = (name, comparison) }
  }

  /// Browsing changes are saved with the document but do not consume Undo steps.
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
    scores = []
    guard let b = comparison.b else {
      comparing = false
      return
    }
    comparing = true
    do {
      try await Task.sleep(for: .milliseconds(120))
      let result = try await engine.scores(a: comparison.a, b: b, sample: comparison.text)
      try Task.checkCancellation()
      scores = result
      comparing = false
    } catch {
      // A newer request owns the progress indicator after cancellation.
      if !Task.isCancelled { comparing = false }
    }
  }
}
