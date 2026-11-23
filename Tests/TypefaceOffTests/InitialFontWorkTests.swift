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

  @Test(arguments: [false, true])
  func initialResultsMatchTheCurrentFonts(changed: Bool) async throws {
    let initial = Comparison()
    let work = InitialFontWork(comparison: initial)
    defer { work.cancel() }
    let initialScores = try #require(try await work.ranking.value(for: initial))
    var current = initial
    if changed { current.a = .init("ArialMT") }
    let ranking = RankingModel(preparation: work)
    #expect(ranking.scores.isEmpty)
    let changes = Mutex(0)
    let rankingChanges = ranking.objectWillChange.sink { changes.withLock { $0 += 1 } }
    defer { rankingChanges.cancel() }
    await ranking.update(current)
    let expectedScores = try await DifferenceEngine().scores(
      a: current.a, b: #require(current.b), sample: current.text)
    #expect(ranking.scores == expectedScores)
    #expect(!ranking.comparing)
    if !changed { #expect(ranking.scores == initialScores) }
    #expect(changes.withLock { $0 } > 0)
  }

  @Test func singleFontPreparationHasNoRanking() async throws {
    let comparison = Comparison(b: nil)
    let work = InitialFontWork(comparison: comparison)
    defer { work.cancel() }
    #expect(try await work.ranking.value(for: comparison) == [])
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
    #expect(initial.text == current.text)
    #expect(initial != current)
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
