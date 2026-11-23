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

struct FontFamilyPicker: View {
  let families: [String]
  let currentFamily: String?
  let allowsNone: Bool
  let choose: (String?) -> Void
  @ObservedObject var ranking: FamilySimilarityModel
  let reference: FontConfiguration?
  let catalog: FontCatalog
  @Environment(\.displayScale) private var scale
  @Environment(\.dismiss) private var dismiss
  @State private var query: String
  @State private var selection: Choice?

  init(
    families: [String], currentFamily: String?, allowsNone: Bool,
    ranking: FamilySimilarityModel = FamilySimilarityModel(),
    reference: FontConfiguration? = nil, catalog: FontCatalog = FontCatalog(),
    choose: @escaping (String?) -> Void
  ) {
    self.families = families
    self.currentFamily = currentFamily
    self.allowsNone = allowsNone
    self.choose = choose
    self.ranking = ranking
    self.reference = reference
    self.catalog = catalog
    _query = State(initialValue: "")
  }

  enum Choice: Hashable {
    case none
    case family(String)

    var title: String {
      switch self {
      case .none: "None"
      case .family(let name): name
      }
    }

    var family: String? {
      switch self {
      case .none: nil
      case .family(let name): name
      }
    }
  }

  private var choices: [Choice] {
    ((allowsNone ? [Choice.none] : [])
      + (reference == nil ? families : ranking.ordered(families)).map(Choice.family)).filter {
        query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
      }
  }

  var body: some View {
    VStack(spacing: 10) {
      PickerSearchField(
        label: "Search installed fonts", text: $query, move: move, submit: confirm,
        cancel: { dismiss() }
      ).padding([.top, .horizontal])
      if reference != nil {
        Picker("Sort fonts", selection: $ranking.sort.settingAfterViewUpdate) {
          ForEach(FamilySimilarityModel.Sort.allCases, id: \.self) {
            Text(verbatim: $0.rawValue).tag($0)
          }
        }.pickerStyle(.segmented).labelsHidden().padding(.horizontal)
        if ranking.sort == .similarity, let reference {
          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
              Text(verbatim: "Similarity to \(reference.face.family) · default settings")
                .lineLimit(2)
              Spacer(minLength: 8)
              Text("Distance").help("Lower is closer")
            }
            if let error = ranking.error {
              Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(
                WorkbenchStyle.ink)
            } else if ranking.comparing {
              GeometryReader { geometry in
                Rectangle().fill(WorkbenchStyle.ink)
                  .frame(
                    width: geometry.size.width * Double(ranking.results.count)
                      / Double(max(1, families.count)))
              }.frame(height: 2)
                .accessibilityLabel("Font comparison progress")
                .accessibilityValue("\(ranking.results.count) of \(families.count)")
              Text(verbatim: "Compared \(ranking.results.count) of \(families.count)")
            }
          }.font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk).padding(
            .horizontal)
        }
      }
      if choices.isEmpty {
        Text("No matching fonts").foregroundStyle(WorkbenchStyle.secondaryInk)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        FontFamilyTable(
          choices: choices, currentFamily: currentFamily, selection: $selection,
          similarity: reference != nil && ranking.sort == .similarity ? ranking.results : nil,
          catalog: catalog, choose: choose, confirm: confirm, cancel: { dismiss() })
      }
    }
    .frame(width: 300, height: 400)
    .background(WorkbenchStyle.paper)
    .foregroundStyle(WorkbenchStyle.ink).tint(WorkbenchStyle.ink)
    .environment(\.colorScheme, .light)
    .onAppear {
      let current = currentFamily.map(Choice.family) ?? .none
      selection = choices.contains(current) ? current : choices.first
    }
    .onChange(of: query) {
      if !choices.contains(where: { $0 == selection }) { selection = choices.first }
    }
    .task(id: request) {
      if reference != nil { await ranking.update(request, catalog: catalog) }
    }
    .onExitCommand { dismiss() }
  }

  private var request: FamilySimilarityModel.Request? {
    guard ranking.sort == .similarity, let reference else { return nil }
    let defaults =
      FontRenderer.isAvailable(reference)
      ? catalog.defaultConfiguration(in: reference.face.family, size: reference.size) : nil
    return .init(reference: defaults ?? reference, scale: scale)
  }

  private func move(_ offset: Int) {
    let choices = choices
    guard !choices.isEmpty else { return }
    let index =
      selection.flatMap { choices.firstIndex(of: $0) } ?? (offset > 0 ? -1 : choices.count)
    selection = choices[min(max(index + offset, 0), choices.count - 1)]
  }

  private func confirm() {
    guard let selection, choices.contains(selection) else { return }
    choose(selection.family)
  }
}
