import TypefaceCore

struct PreparedSearch<Input: Equatable & Sendable, Output: Sendable>: Sendable {
  let input: Input
  private let task: Task<Output, any Error>

  init(input: Input, load: @escaping @Sendable (Input) async throws -> Output) {
    self.input = input
    task = Task.detached(priority: .userInitiated) { try await load(input) }
  }

  func value(for input: Input) async throws -> Output? {
    guard self.input == input else { return nil }
    return try await task.value
  }

  func cancel() { task.cancel() }
}

struct InitialFontWork: Sendable {
  let rankingEngine: DifferenceEngine
  let ranking: PreparedSearch<Comparison, [GlyphDifference]>

  init(comparison: Comparison) {
    let engine = DifferenceEngine()
    rankingEngine = engine
    ranking = PreparedSearch(input: comparison) { comparison in
      #if TYPEFACEOFF_STARTUP_BENCHMARK
        StartupDiagnostics.markBackground("rankingPreparationStarted")
        defer { StartupDiagnostics.markBackground("rankingPreparationFinished") }
      #endif
      guard let b = comparison.b else { return [] }
      return try await engine.scores(a: comparison.a, b: b, sample: comparison.text)
    }
  }

  func cancel() {
    ranking.cancel()
  }
}
