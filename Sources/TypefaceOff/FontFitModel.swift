import SwiftUI
import TypefaceCore

@MainActor
final class FontFitModel: ObservableObject {
  struct Request: Hashable {
    let a: FontConfiguration
    let b: FontConfiguration
    let text: String
    let options: FontFitOptions
    let scale: Double

    func hasSameInputs(as other: Self?) -> Bool {
      a == other?.a && b == other?.b && text == other?.text && scale == other?.scale
    }
  }

  @Published private(set) var result: FontFitResult?
  @Published private(set) var running = false
  @Published private(set) var error: String?
  @Published private(set) var searchImproved = false
  private var generation = UUID()
  private var task: Task<Void, Never>?
  private var request: Request?
  private let load:
    @Sendable (Request, FontConfiguration) async throws -> AsyncThrowingStream<FontFitResult, Error>

  init(engine: FontFitEngine = FontFitEngine(), catalog: FontCatalog = FontCatalog()) {
    load = { request, candidate in
      // A fixed corpus keeps cumulative scores comparable across successive searches.
      await engine.fit(
        a: request.a, b: candidate, options: request.options,
        corpus: .fitting(reference: request.a, candidate: request.b, text: request.text),
        catalog: catalog,
        scale: request.scale, budget: .refine)
    }
  }

  init(
    load:
      @escaping @Sendable (Request, FontConfiguration) async throws -> AsyncThrowingStream<
        FontFitResult, Error
      >
  ) {
    self.load = load
  }

  func start(_ request: Request?) {
    stop()
    if request?.hasSameInputs(as: self.request) != true { result = nil }
    let previous = result
    self.request = request
    error = nil
    searchImproved = false
    guard let request else { return }
    running = true
    let generation = self.generation
    let load = self.load
    task = Task {
      do {
        let stream = try await load(request, previous?.proposed ?? request.b)
        for try await result in stream {
          try Task.checkCancellation()
          guard self.generation == generation else { return }
          self.searchImproved = result.improved
          self.result = FontFitResult(
            proposed: result.proposed,
            originalScore: previous?.originalScore ?? result.originalScore,
            score: result.score, evaluations: (previous?.evaluations ?? 0) + result.evaluations,
            finished: result.finished)
        }
      } catch {
        guard self.generation == generation else { return }
        if !(error is CancellationError) { self.error = error.localizedDescription }
      }
      if self.generation == generation { self.running = false }
    }
  }

  func stop() {
    generation = UUID()
    task?.cancel()
    task = nil
    running = false
  }

  func apply(to model: WorkbenchModel, undoManager: UndoManager?) -> Bool {
    guard let request, let result, result.improved,
      model.comparison.a == request.a, model.comparison.b == request.b,
      model.comparison.text == request.text
    else { return false }
    stop()
    model.edit("Match fonts", undoManager: undoManager) {
      $0.b = result.proposed
      $0.calibrate()
    }
    return true
  }
}
