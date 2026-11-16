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
    .background(WorkbenchStyle.sheet)
    .environment(\.colorScheme, .light)
    .task(id: request) { await search.update(request) }
    .onChange(of: search.answer) { _, answer in
      guard let answer, answer.request == request else { return }
      selection = answer.results.first?.id
      if confirming == answer.request, let first = answer.results.first {
        choose(first.glyph)
      }
      confirming = nil
    }
    .onExitCommand { dismiss() }
  }

  @ViewBuilder private var content: some View {
    if query.isEmpty {
      Text(
        verbatim:
          "Search by name, such as “left arrow”; by character, such as é; or by code point, such as U+2192."
      )
      .multilineTextAlignment(.center).foregroundStyle(.secondary).padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("Character search hint")
    } else if let answer = search.answer, !answer.results.isEmpty {
      list(answer)
    } else if isAnswered {
      Text("No matching characters").foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("No matching characters")
    } else {
      ProgressView().controlSize(.small).accessibilityLabel("Searching characters")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func list(_ answer: CharacterSearchModel.Answer) -> some View {
    let names = CharacterSearchRow.names(of: answer.request.fonts)
    return ScrollViewReader { proxy in
      List(answer.results, selection: $selection) { result in
        Button {
          choose(result.glyph)
        } label: {
          CharacterSearchRow(
            result: result, fonts: answer.request.fonts, names: names,
            spacingOnly: comparison.spacing && !comparison.shape)
        }.buttonStyle(.plain)
          .accessibilityLabel(Text(verbatim: CharacterSearchRow.label(result, names: names)))
          .tag(result.id).id(result.id)
      }
      .onKeyPress(.return) {
        confirm()
        return .handled
      }
      .onChange(of: selection) { _, id in
        if let id { proxy.scrollTo(id) }
      }
    }
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
