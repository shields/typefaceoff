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

extension SimilarityScore {
  var formattedDistance: String {
    total.formatted(.number.precision(.fractionLength(3)).grouping(.never))
  }
}

@MainActor
final class FamilySimilarityModel: ObservableObject {
  enum Sort: String, CaseIterable {
    case name = "Name"
    case similarity = "Similarity"
  }
  struct Request: Hashable {
    let reference: FontConfiguration
    let scale: Double
  }

  @Published var sort = Sort.name
  @Published private(set) var results: [String: FamilySimilarity] = [:]
  @Published private(set) var comparing = false
  @Published private(set) var error: String?
  private var generation = UUID()
  private let load:
    @Sendable (FontConfiguration, FontCatalog, Double) async throws -> AsyncThrowingStream<
      FamilySimilarity, Error
    >

  init(engine: FontSimilarityEngine = .shared) {
    load = { await engine.rankFamilies(reference: $0, catalog: $1, scale: $2) }
  }

  init(
    load:
      @escaping @Sendable (FontConfiguration, FontCatalog, Double) async throws ->
      AsyncThrowingStream<FamilySimilarity, Error>
  ) {
    self.load = load
  }

  func ordered(_ families: [String]) -> [String] {
    guard sort == .similarity else { return families }
    return families.sorted {
      let left = results[$0]?.score?.total ?? .infinity
      let right = results[$1]?.score?.total ?? .infinity
      return left == right ? $0.localizedStandardCompare($1) == .orderedAscending : left < right
    }
  }

  func update(_ request: Request?, catalog: FontCatalog) async {
    let generation = UUID()
    self.generation = generation
    results = [:]
    error = nil
    comparing = false
    guard sort == .similarity, let request else { return }
    comparing = true
    var collected: [String: FamilySimilarity] = [:]
    var published = ContinuousClock.now
    do {
      let stream = try await load(request.reference, catalog, request.scale)
      for try await result in stream {
        try Task.checkCancellation()
        guard self.generation == generation else { return }
        collected[result.family] = result
        if ContinuousClock.now - published >= .milliseconds(200) {
          results = collected
          published = .now
        }
      }
      try Task.checkCancellation()
      guard self.generation == generation else { return }
      results = collected
    } catch {
      guard self.generation == generation else { return }
      if !(error is CancellationError) { self.error = error.localizedDescription }
    }
    comparing = false
  }
}
