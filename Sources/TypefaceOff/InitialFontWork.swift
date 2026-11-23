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
