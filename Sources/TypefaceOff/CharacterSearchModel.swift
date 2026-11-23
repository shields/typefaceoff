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
final class CharacterSearchModel: ObservableObject {
  struct Request: Equatable {
    let query: String
    let fonts: [FontConfiguration]

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.query.unicodeScalars.elementsEqual(rhs.query.unicodeScalars) && lhs.fonts == rhs.fonts
    }
  }

  /// The latest finished search, which trails the current request while a search runs.
  struct Answer: Equatable {
    let request: Request
    let results: [CharacterSearchResult]
  }

  typealias Load = @Sendable (String, [FontConfiguration]) async throws -> [CharacterSearchResult]

  @Published private(set) var answer: Answer?
  private var token = UUID()
  private let load: Load

  init(load: @escaping Load) {
    self.load = load
  }

  func update(_ request: Request) async {
    let fuzzWork = FuzzDiagnostics.shared.beginWork("character-search")
    defer {
      FuzzDiagnostics.shared.endWork(
        fuzzWork, kind: "character-search", outcome: Task.isCancelled ? "cancelled" : "completed")
    }
    let token = UUID()
    self.token = token
    do {
      let results = try await load(request.query, request.fonts)
      try Task.checkCancellation()
      guard self.token == token else { return }
      answer = Answer(request: request, results: results)
    } catch {
      // Cancelled or superseded searches must not replace the current request's results.
    }
  }
}
