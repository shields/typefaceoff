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
  }

  @Published private(set) var result: FontFitResult?
  @Published private(set) var running = false
  @Published private(set) var error: String?
  private var generation = UUID()
  private var task: Task<Void, Never>?
  private var request: Request?
  private let load:
    @Sendable (Request, Bool) async throws -> AsyncThrowingStream<FontFitResult, Error>

  init(engine: FontFitEngine = FontFitEngine(), catalog: FontCatalog = FontCatalog()) {
    load = { request, refine in
      await engine.fit(
        a: request.a, b: request.b, options: request.options,
        corpus: .fitting(reference: request.a, candidate: request.b, text: request.text),
        catalog: catalog,
        scale: request.scale, budget: refine ? .refine : .quick, refine: refine)
    }
  }

  init(
    load:
      @escaping @Sendable (Request, Bool) async throws -> AsyncThrowingStream<FontFitResult, Error>
  ) {
    self.load = load
  }

  func start(_ request: Request?, refine: Bool = false) {
    stop()
    if !refine || self.request != request { result = nil }
    self.request = request
    error = nil
    guard let request else { return }
    running = true
    let generation = self.generation
    let load = self.load
    task = Task {
      do {
        let stream = try await load(request, refine)
        for try await result in stream {
          try Task.checkCancellation()
          guard self.generation == generation else { return }
          self.result = result
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
