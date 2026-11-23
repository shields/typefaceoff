// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI
import TypefaceCore

@MainActor
final class FontFitModel: ObservableObject {
  struct Request {
    let a: FontConfiguration
    let b: FontConfiguration
    let text: String
    let options: FontFitOptions
    let scale: Double

    func hasSameInputs(as other: Self?) -> Bool {
      guard let other else { return false }
      return a == other.a && b == other.b && scale == other.scale
        && text.unicodeScalars.elementsEqual(other.text.unicodeScalars)
    }
  }

  @Published private(set) var result: FontFitResult?
  @Published private(set) var running = false
  @Published private(set) var error: String?
  @Published private(set) var searchImproved = false
  private var generation = UUID()
  private var task: Task<Void, Never>?
  private var request: Request?
  var searchOptions: FontFitOptions? { request?.options }
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

  @discardableResult func stop() -> Task<Void, Never>? {
    generation = UUID()
    let previous = task
    task?.cancel()
    task = nil
    running = false
    return previous
  }

  func apply(to model: WorkbenchModel, undoManager: UndoManager?) -> Bool {
    guard !running, let request, let result, result.improved,
      model.comparison.a == request.a, model.comparison.b == request.b,
      model.comparison.text.unicodeScalars.elementsEqual(request.text.unicodeScalars)
    else { return false }
    stop()
    model.edit("Match fonts", undoManager: undoManager) {
      $0.b = result.proposed
      $0.calibrate()
    }
    return true
  }
}
