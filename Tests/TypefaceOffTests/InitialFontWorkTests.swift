import Combine
import Synchronization
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct InitialFontWorkTests {
  @Test func preparationStartsBeforeConsumptionAndRejectsDifferentInputs() async throws {
    let (events, started) = AsyncStream<Void>.makeStream()
    let gate = PreparedSearchGate<Int>(started: started)
    let search = PreparedSearch(input: 1) { _ in await gate.load() }
    defer { search.cancel() }
    var iterator = events.makeAsyncIterator()
    #expect(await iterator.next() != nil)
    #expect(try await search.value(for: 2) == nil)
    await gate.finish(42)
    #expect(try await search.value(for: 1) == 42)
    #expect(try await search.value(for: 1) == 42)
    #expect(try await search.value(for: 2) == nil)
  }

  @Test func cancellingPreparationDoesNotPublishAResult() async {
    let (events, started) = AsyncStream<Void>.makeStream()
    let search = PreparedSearch(input: 1) { input in
      started.yield(())
      try await Task.sleep(for: .seconds(60))
      return input
    }
    var iterator = events.makeAsyncIterator()
    #expect(await iterator.next() != nil)
    search.cancel()
    await #expect(throws: CancellationError.self) { try await search.value(for: 1) }
  }

  @Test func cancelledPreviewConsumersCannotPublishPreparedResults() async {
    let (events, started) = AsyncStream<Void>.makeStream()
    let gate = PreparedSearchGate<[String: FontFeaturePreview]>(started: started)
    let config = FontConfiguration("HelveticaNeue")
    let search = PreparedSearch(input: config) { _ in await gate.load() }
    defer { search.cancel() }
    let model = FeaturePreviewModel(preparation: search)
    let request = Task { await model.update(config) }
    var iterator = events.makeAsyncIterator()
    #expect(await iterator.next() != nil)
    request.cancel()
    await gate.finish([:])
    await request.value
    #expect(model.result == nil)
  }

  @Test(arguments: [false, true])
  func initialResultsMatchTheCurrentFonts(changed: Bool) async throws {
    let initial = Comparison()
    let work = InitialFontWork(comparison: initial)
    defer { work.cancel() }
    let initialScores = try #require(try await work.ranking.value(for: initial))
    let preparedPreview = try #require(work.previews(for: .a))
    _ = try await preparedPreview.value(for: preparedPreview.input)
    var current = initial
    if changed { current.a = .init("ArialMT") }
    let ranking = RankingModel(preparation: work)
    let previews = FeaturePreviewModel(preparation: preparedPreview)
    #expect(ranking.scores.isEmpty)
    let changes = Mutex(0)
    let rankingChanges = ranking.objectWillChange.sink { changes.withLock { $0 += 1 } }
    let previewChanges = previews.objectWillChange.sink { changes.withLock { $0 += 1 } }
    defer {
      rankingChanges.cancel()
      previewChanges.cancel()
    }
    await ranking.update(current)
    var config = current.a
    config.size = 21
    await previews.update(config)
    #expect(previews.result?.config == config)
    let expectedScores = try await DifferenceEngine().scores(
      a: current.a, b: #require(current.b), sample: current.text)
    #expect(ranking.scores == expectedScores)
    #expect(!ranking.comparing)
    if !changed { #expect(ranking.scores == initialScores) }
    let expectedPreviews = try await FontFeaturePreviewEngine.shared.previews(config: config)
    #expect(previews.result?.previews.mapValues(\.text) == expectedPreviews.mapValues(\.text))
    #expect(changes.withLock { $0 } > 0)
  }

  @Test func singleFontPreparationHasNoSecondPreviewOrRanking() async throws {
    var comparison = Comparison(b: nil)
    comparison.a.leading = 32
    let work = InitialFontWork(comparison: comparison)
    defer { work.cancel() }
    #expect(try await work.ranking.value(for: comparison) == [])
    #expect(work.previews(for: .a)?.input.size == 21)
    #expect(work.previews(for: .a)?.input.leading == nil)
    #expect(work.previews(for: .b) == nil)
  }

  @Test func canonicallyEquivalentTextStillUsesItsOwnCharacterIdentities() async throws {
    var initial = Comparison()
    initial.sample = .custom
    initial.customText = ";"
    let work = InitialFontWork(comparison: initial)
    defer { work.cancel() }
    _ = try await work.ranking.value(for: initial)
    var current = initial
    current.customText = "\u{037E}"
    #expect(initial == current)
    let ranking = RankingModel(preparation: work)
    await ranking.update(current)
    #expect(ranking.scores.contains { $0.id == Array("\u{037E}".unicodeScalars) })
  }
}

private actor PreparedSearchGate<Value: Sendable> {
  let started: AsyncStream<Void>.Continuation
  private var waiting: CheckedContinuation<Value, Never>?

  init(started: AsyncStream<Void>.Continuation) { self.started = started }

  func load() async -> Value {
    await withCheckedContinuation {
      waiting = $0
      started.yield(())
    }
  }

  func finish(_ value: Value) {
    waiting!.resume(returning: value)
    waiting = nil
  }
}
