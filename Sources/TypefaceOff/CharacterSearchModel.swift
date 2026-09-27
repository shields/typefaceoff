import SwiftUI
import TypefaceCore

@MainActor
final class CharacterSearchModel: ObservableObject {
  struct Request: Equatable {
    let query: String
    let fonts: [FontConfiguration]
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
