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
  private let a: PreparedSearch<FontConfiguration, [String: FontFeaturePreview]>
  private let b: PreparedSearch<FontConfiguration, [String: FontFeaturePreview]>?

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
    a = Self.preview(comparison.a)
    b = comparison.b.map(Self.preview)
  }

  func previews(for side: Side) -> PreparedSearch<FontConfiguration, [String: FontFeaturePreview]>?
  {
    side == .a ? a : b
  }

  func cancel() {
    ranking.cancel()
    a.cancel()
    b?.cancel()
  }

  private static func preview(_ config: FontConfiguration)
    -> PreparedSearch<FontConfiguration, [String: FontFeaturePreview]>
  {
    var config = config
    config.size = 21
    return PreparedSearch(input: config) {
      #if TYPEFACEOFF_STARTUP_BENCHMARK
        StartupDiagnostics.markBackground("previewPreparationStarted-\($0.postScriptName)")
        defer {
          StartupDiagnostics.markBackground("previewPreparationFinished-\($0.postScriptName)")
        }
      #endif
      return try await FontFeaturePreviewEngine.shared.previews(config: $0)
    }
  }
}
