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

import Foundation
import SwiftUI
import TypefaceCore

@MainActor
final class LanguageBrowserModel: ObservableObject {
  struct Request: Equatable, Sendable {
    let a: FontConfiguration
    let b: FontConfiguration?

    init(_ comparison: Comparison) {
      a = LanguageCoverageEngine.key(comparison.a)
      b = comparison.b.map(LanguageCoverageEngine.key)
    }
  }

  typealias Load = @Sendable () async throws -> LanguageDatabase
  typealias Check =
    @Sendable (
      [LanguageRecord], FontConfiguration, [String],
      @escaping @Sendable ([String: LanguageCoverage]) async -> Void
    ) async throws -> Void

  @Published var ordering = LanguageOrdering()
  @Published var filter: LanguageFilter
  @Published var coverageFilter: LanguageCoverageFilter
  @Published var selection: String?
  @Published var orthographySelection: String?
  @Published var categories: Set<LanguageCategory>
  @Published var scrollID: String?
  @Published var detailScrollID: String?
  @Published var expanded: Set<String>
  @Published private(set) var database: LanguageDatabase?
  @Published private(set) var a: [String: LanguageCoverage]
  @Published private(set) var b: [String: LanguageCoverage]
  @Published private(set) var checking: Bool
  @Published private(set) var problem: String?
  private let check: Check
  private let load: Load
  private var token: UUID
  private var request: Request?

  init(
    engine: LanguageCoverageEngine = .shared,
    load: @escaping Load = LanguageBrowserModel.loadDatabase,
    check: Check? = nil
  ) {
    self.check =
      check ?? { languages, font, priority, progress in
        _ = try await engine.results(
          for: languages, font: font, priority: priority, progress: progress)
      }
    self.load = load
    filter = LanguageFilter()
    coverageFilter = .all
    selection = nil
    orthographySelection = nil
    categories = [.base]
    scrollID = nil
    detailScrollID = nil
    expanded = []
    database = nil
    a = [:]
    b = [:]
    checking = false
    problem = nil
    token = UUID()
  }

  @concurrent
  static func loadDatabase() async throws -> LanguageDatabase { LanguageDatabase.shared }

  var comparing: Bool { request?.b != nil }
  var maximumSpeakers: Int { database?.languages.compactMap(\.speakers).max() ?? 1_000_000_000 }
  var rows: [LanguageRecord] {
    let filtered = (database?.languages ?? []).filter {
      filter.includes($0)
        && coverageFilter.includes(a: a[$0.id]?.complete($0), b: b[$0.id]?.complete($0))
    }
    return ordering.sorted(filtered, a: a, b: b)
  }
  var hiddenMatches: Int {
    (database?.languages ?? []).count { $0.matches(filter.query) && !filter.includes($0) }
  }
  var selectedLanguage: LanguageRecord? {
    database?.languages.first { $0.id == selection }
  }
  var selectedOrthography: OrthographyRecord? {
    let orthographies = selectedLanguage?.orthographies(showHistorical: filter.showHistorical) ?? []
    return orthographies.first { $0.id == orthographySelection } ?? orthographies.first
  }

  func clearFilters() {
    filter.clear()
    coverageFilter = .all
  }

  func update(_ request: Request) async {
    if self.request == request && !checking && problem == nil,
      let database, a.count == database.languages.count,
      request.b == nil || b.count == database.languages.count
    {
      return
    }
    self.request = request
    if !LanguageCoverageFilter.options(comparing: request.b != nil).contains(coverageFilter) {
      coverageFilter = .all
    }
    let token = UUID()
    self.token = token
    checking = true
    problem = nil
    a = [:]
    b = [:]
    let work = FuzzDiagnostics.shared.beginWork("language-coverage")
    defer {
      FuzzDiagnostics.shared.endWork(
        work, kind: "language-coverage",
        outcome: Task.isCancelled ? "cancelled" : problem == nil ? "completed" : "failed")
    }
    do {
      let database = try await load()
      try Task.checkCancellation()
      guard self.token == token else { return }
      self.database = database
      if selection == nil { selection = rows.first?.id }
      let priority = [selection, scrollID].compactMap { $0 } + rows.prefix(16).map(\.id)
      try await withThrowingTaskGroup(of: Void.self) { group in
        for (side, font) in [(Side.a, request.a), (.b, request.b)].compactMap({ side, font in
          font.map { (side, $0) }
        }) {
          group.addTask { [check, weak self] in
            try await check(database.languages, font, priority) {
              [weak self] partial in
              await self?.accept(partial, side: side, token: token)
            }
          }
        }
        try await group.waitForAll()
      }
      try Task.checkCancellation()
      if self.token == token { checking = false }
    } catch is CancellationError {
      if self.token == token { checking = false }
    } catch {
      if self.token == token {
        problem = error.localizedDescription
        checking = false
      }
    }
  }

  private func accept(_ partial: [String: LanguageCoverage], side: Side, token: UUID) {
    guard self.token == token, !Task.isCancelled else { return }
    if side == .a { a = partial } else { b = partial }
  }
}
