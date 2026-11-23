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

/// Browsing results leaves the inspected character unchanged until one is chosen.
struct CharacterSearchPicker: View {
  let comparison: Comparison
  let choose: (String) -> Void
  @StateObject private var search: CharacterSearchModel
  @Environment(\.dismiss) private var dismiss
  @State private var query: String
  @State private var selection: [Unicode.Scalar]?
  @State private var confirming: CharacterSearchModel.Request?

  init(
    comparison: Comparison,
    search: CharacterSearchModel? = nil,
    load: @escaping CharacterSearchModel.Load = CharacterSearch.results(for:fonts:),
    choose: @escaping (String) -> Void
  ) {
    self.comparison = comparison
    self.choose = choose
    _search = StateObject(wrappedValue: search ?? CharacterSearchModel(load: load))
    _query = State(initialValue: "")
    _selection = State(initialValue: nil)
    _confirming = State(initialValue: nil)
  }

  private var request: CharacterSearchModel.Request {
    .init(query: query, fonts: [comparison.a, comparison.b].compactMap { $0 })
  }
  private var isAnswered: Bool { search.answer?.request == request }

  var body: some View {
    VStack(spacing: 10) {
      PickerSearchField(
        label: "Search Unicode characters", text: $query, move: move, submit: confirm,
        cancel: { dismiss() }
      ).padding([.top, .horizontal])
      content
    }
    .frame(width: 440, height: 460)
    .background(WorkbenchStyle.paper)
    .foregroundStyle(WorkbenchStyle.ink).tint(WorkbenchStyle.ink)
    .preferredColorScheme(.light)
    .task(id: request) { await search.update(request) }
    .onChange(of: search.answer) { _, answer in
      guard let answer, answer.request == request else { return }
      selection = answer.results.first?.id
      if confirming == answer.request, let first = answer.results.first {
        choose(first.glyph)
      }
      confirming = nil
    }
  }

  @ViewBuilder private var content: some View {
    if query.isEmpty {
      Text(
        verbatim:
          "Search by name, such as “left arrow”; by character, such as é; or by code point, such as U+2192."
      )
      .multilineTextAlignment(.center).foregroundStyle(WorkbenchStyle.secondaryInk).padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("Character search hint")
    } else if let answer = search.answer, !answer.results.isEmpty {
      list(answer)
    } else if isAnswered {
      Text("No matching characters").foregroundStyle(WorkbenchStyle.secondaryInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("No matching characters")
    } else {
      ProgressView().controlSize(.small).accessibilityLabel("Searching characters")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func list(_ answer: CharacterSearchModel.Answer) -> some View {
    CharacterSearchTable(
      results: answer.results, fonts: answer.request.fonts, selection: $selection,
      spacingOnly: comparison.spacing && !comparison.shape, choose: choose, confirm: confirm,
      cancel: { dismiss() })
  }

  private func move(_ offset: Int) {
    guard let ids = search.answer?.results.map(\.id), !ids.isEmpty else { return }
    let index = selection.flatMap { ids.firstIndex(of: $0) } ?? (offset > 0 ? -1 : ids.count)
    selection = ids[min(max(index + offset, 0), ids.count - 1)]
  }

  /// Returning before the query's results arrive chooses from them once they do, never from
  /// an earlier query's results or a later one's.
  private func confirm() {
    guard isAnswered else {
      confirming = request
      return
    }
    if let result = search.answer?.results.first(where: { $0.id == selection }) {
      choose(result.glyph)
    }
  }
}

struct CharacterSearchRow: View {
  let result: CharacterSearchResult
  let fonts: [FontConfiguration]
  let names: [String]
  let spacingOnly: Bool

  var body: some View {
    HStack(spacing: 10) {
      preview.frame(width: 46, height: 38).clipShape(RoundedRectangle(cornerRadius: 2))
        .allowsHitTesting(false).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: unicodeDescription(result.glyph)).lineLimit(2)
        if let unavailable = Self.unavailability(result, names: names) {
          Text(verbatim: "⚠︎ " + unavailable).font(.system(size: 11))
            .foregroundStyle(WorkbenchStyle.ink)
        }
      }
      Spacer(minLength: 0)
    }.contentShape(Rectangle())
  }

  /// Only fonts that have the glyph draw it; with one such font, its ink draws as shared.
  @ViewBuilder private var preview: some View {
    let drawn = zip(fonts, result.supported).filter(\.1).map(\.0)
    if let first = drawn.first, let last = drawn.last {
      GlyphDifferencePreview(glyph: result.glyph, a: first, b: last, spacingOnly: spacingOnly)
    } else {
      Color.white
    }
  }

  /// Families name the fonts unless both share one; a missing font has only the name it was
  /// configured with.
  static func names(of fonts: [FontConfiguration]) -> [String] {
    let families = fonts.map { FontRenderer.isAvailable($0) ? $0.face.family : $0.postScriptName }
    guard Set(families).count < families.count else { return families }
    return fonts.map {
      FontRenderer.isAvailable($0) ? "\($0.face.family) \($0.face.style)" : $0.postScriptName
    }
  }

  static func label(_ result: CharacterSearchResult, names: [String]) -> String {
    unicodeDescription(result.glyph)
      + (unavailability(result, names: names).map { ". \($0)" } ?? "")
  }

  static func unavailability(_ result: CharacterSearchResult, names: [String]) -> String? {
    var missing: [String] = []
    for (name, supported) in zip(names, result.supported) where !supported {
      if !missing.contains(name) { missing.append(name) }
    }
    guard !missing.isEmpty else { return nil }
    return "Unavailable in \(missing.joined(separator: " and "))"
  }
}
