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

  private enum Choice: Hashable {
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
        }.pickerStyle(.segmented).padding(.horizontal)
        if ranking.sort == .similarity, let reference {
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Similarity to \(reference.face.family) · default settings")
              .font(.caption)
            if let error = ranking.error {
              Text(verbatim: error).foregroundStyle(.orange)
            } else if ranking.comparing {
              ProgressView(
                value: Double(ranking.results.count), total: Double(max(1, families.count)))
              Text(verbatim: "Compared \(ranking.results.count) of \(families.count)")
            }
          }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
      }
      ScrollViewReader { proxy in
        if choices.isEmpty {
          Text("No matching fonts").foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(choices, id: \.self, selection: $selection) { choice in
            Button {
              choose(choice.family)
            } label: {
              HStack {
                Text(verbatim: choice.title).lineLimit(1)
                Spacer()
                if reference != nil, ranking.sort == .similarity, let family = choice.family {
                  if let result = ranking.results[family] {
                    Text(
                      verbatim: result.score.map(\.formattedDistance) ?? "Unavailable"
                    )
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .help(result.unavailableReason ?? "Heuristic distance; lower is closer")
                  } else {
                    Text("Pending").font(.caption).foregroundStyle(.secondary)
                  }
                }
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).tag(choice).id(choice)
          }
          .onKeyPress(.return) {
            confirm()
            return .handled
          }
          .onChange(of: selection) { _, choice in
            if let choice { proxy.scrollTo(choice) }
          }
          // Live similarity results and toggling sort order both reorder `choices` without
          // changing `selection`, so keep the highlighted row in view for either.
          .onChange(of: ranking.results.count) {
            if let selection { proxy.scrollTo(selection) }
          }
          .onChange(of: ranking.sort) {
            if let selection { proxy.scrollTo(selection) }
          }
        }
      }
    }
    .frame(width: 300, height: 400)
    .background(WorkbenchStyle.sheet)
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
