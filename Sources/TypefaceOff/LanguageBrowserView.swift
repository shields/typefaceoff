import SwiftUI
import TypefaceCore

struct LanguageBrowserView: View {
  @ObservedObject var browser: LanguageBrowserModel
  let comparison: Comparison
  let inspect: (String) -> Void
  let useSpecimen: (String) -> Void
  @State private var threshold: String

  init(
    browser: LanguageBrowserModel, comparison: Comparison, inspect: @escaping (String) -> Void,
    useSpecimen: @escaping (String) -> Void
  ) {
    self.browser = browser
    self.comparison = comparison
    self.inspect = inspect
    self.useSpecimen = useSpecimen
    _threshold = State(initialValue: SpeakerThreshold.format(browser.filter.minimumSpeakers))
  }

  var body: some View {
    VStack(spacing: 0) {
      filters
      Divider()
      if let problem = browser.problem {
        Text(verbatim: "Language coverage failed: \(problem)").foregroundStyle(.red).padding()
          .accessibilityLabel(Text(verbatim: "Language coverage failed: \(problem)"))
          .accessibilityIdentifier("Language coverage error message")
      }
      if browser.database == nil && browser.problem == nil {
        ProgressView("Loading languages").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if browser.database != nil {
        HStack(spacing: 0) {
          languageList.frame(minWidth: 180, idealWidth: 210, maxWidth: 260)
          Divider()
          detail.frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .onChange(of: browser.filter.minimumSpeakers) {
      threshold = SpeakerThreshold.format(browser.filter.minimumSpeakers)
    }
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Search languages", text: $browser.filter.query)
          .accessibilityLabel("Language query")
          .accessibilityIdentifier("Language search field")
          .help("Search language names, autonyms, ISO codes, and scripts")
        Toggle("Show historical", isOn: $browser.filter.showHistorical).toggleStyle(.checkbox)
          .accessibilityIdentifier("Language historical toggle")
      }
      HStack(alignment: .top, spacing: 8) {
        Text("Minimum speakers").font(.caption).frame(width: 90, height: 22, alignment: .leading)
        VStack(spacing: 4) {
          Slider(
            value: Binding(
              get: { SpeakerThreshold.position(browser.filter.minimumSpeakers) },
              set: { browser.filter.minimumSpeakers = SpeakerThreshold.value($0) }),
            in: 0...SpeakerThreshold.position(browser.maximumSpeakers)
          )
          .frame(height: 22)
          .accessibilityLabel("Language speaker threshold")
          .accessibilityIdentifier("Language speaker slider")
          .help("Logarithmic scale; All removes the speaker cutoff")
          GeometryReader { geometry in
            let ticks = Array(
              Set([
                0, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000,
                browser.maximumSpeakers,
              ])
            ).sorted()
            ForEach(ticks.filter { $0 <= browser.maximumSpeakers }, id: \.self) { value in
              Text(verbatim: SpeakerThreshold.format(value)).font(.system(size: 9)).foregroundStyle(
                .secondary
              )
              .position(
                x: geometry.size.width * SpeakerThreshold.position(value)
                  / SpeakerThreshold.position(browser.maximumSpeakers), y: 6)
            }
          }.frame(height: 12)
        }
        TextField("Minimum speaker count", text: $threshold)
          .frame(width: 72, height: 22)
          .accessibilityLabel("Minimum language speakers")
          .accessibilityIdentifier("Language speaker field")
          .onSubmit {
            if let value = SpeakerThreshold.parse(threshold) {
              browser.filter.minimumSpeakers = min(value, browser.maximumSpeakers)
            }
            threshold = SpeakerThreshold.format(browser.filter.minimumSpeakers)
          }
          .help(
            "Enter All or a count such as 100k or 8.3M; the catalog's largest count is the limit")
      }
      HStack {
        Picker("Language coverage", selection: $browser.coverageFilter) {
          ForEach(LanguageCoverageFilter.options(comparing: comparison.b != nil), id: \.self) {
            Text(verbatim: $0.rawValue).tag($0)
          }
        }.accessibilityIdentifier("Language coverage picker").frame(maxWidth: 200)
        Text(verbatim: "\(browser.rows.count) languages").font(.caption).foregroundStyle(.secondary)
        if browser.checking {
          ProgressView().controlSize(.small).accessibilityLabel("Checking language coverage")
        }
        Spacer(minLength: 0)
        Button("Clear filters", action: browser.clearFilters).accessibilityIdentifier(
          "Language clear filters button")
      }
      if !browser.filter.query.isEmpty && browser.hiddenMatches > 0 {
        Text(
          verbatim:
            "\(browser.hiddenMatches) matching languages are hidden by the speaker or historical filters."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }.padding(12)
  }

  private var languageList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        ForEach(browser.rows) { language in
          let choose = {
            browser.selection = language.id
            browser.orthographySelection = nil
          }
          Button(action: choose) {
            VStack(alignment: .leading, spacing: 3) {
              Text(verbatim: language.name).font(.headline)
              Text(
                verbatim:
                  "\(language.id) · \(language.historical ? "Historical" : language.speakers.map(SpeakerThreshold.format) ?? "Unknown speakers")"
              ).font(.caption).foregroundStyle(.secondary)
              HStack {
                Text(verbatim: "A: \(state(browser.a[language.id], language: language))")
                if comparison.b != nil {
                  Text(verbatim: "B: \(state(browser.b[language.id], language: language))")
                }
              }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
              .background(
                browser.selection == language.id ? WorkbenchStyle.accent.opacity(0.18) : .clear,
                in: RoundedRectangle(cornerRadius: 5))
          }.buttonStyle(.plain).id(language.id)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("Language row \(language.id)")
            .accessibilityLabel("Browse \(language.name)")
            .accessibilityAction { choose() }
            .accessibilityAddTraits(browser.selection == language.id ? .isSelected : [])
        }
        if browser.rows.isEmpty {
          Text("No languages match these filters.").foregroundStyle(.secondary).padding()
            .accessibilityLabel("No languages match these filters.")
            .accessibilityIdentifier("Language empty list message")
        }
      }.scrollTargetLayout().padding(6).scrollAreaIdentifier("Language list scroll area")
    }.scrollPosition(id: $browser.scrollID, anchor: .top)
  }

  private func state(_ coverage: LanguageCoverage?, language: LanguageRecord) -> String {
    guard let coverage else { return "Checking" }
    return !coverage.available
      ? "Font unavailable" : coverage.complete(language) ? "Complete" : "Incomplete"
  }

  private var detail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let language = browser.selectedLanguage,
          !language.historical || browser.filter.showHistorical
        {
          Text(verbatim: language.name).font(.title2).id("\(language.id)/name")
          Text(
            verbatim: ([language.id] + language.autonyms.filter { !$0.isEmpty }).joined(
              separator: " · ")
          )
          .foregroundStyle(.secondary).textSelection(.enabled)
          Text(
            verbatim:
              "\(language.speakers.map { "\($0.formatted()) speakers" } ?? "Speaker count unknown")\(language.speakersDate.map { " (\($0))" } ?? "") · \(language.validity) data\(language.historical ? " · Historical" : "")"
          ).font(.caption)
          Text("Character coverage does not assess joining, mark placement, or visual quality.")
            .font(.caption).foregroundStyle(.secondary)
          sources(language)
          ForEach(language.orthographies(showHistorical: browser.filter.showHistorical)) {
            orthography in
            let choose = { browser.orthographySelection = orthography.id }
            Button(action: choose) {
              VStack(alignment: .leading, spacing: 4) {
                Text(
                  verbatim:
                    "\(orthography.script) (\(orthography.scriptCode))\(orthography.historical ? " · Historical" : "")\(orthography.grouped ? " · Required group" : "")"
                )
                Text(verbatim: summary(language, orthography: orthography, category: .base)).font(
                  .caption
                ).foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).padding(8)
              .accessibilityElement(children: .ignore)
              .accessibilityAddTraits(.isButton)
              .accessibilityLabel("Select \(orthography.script) orthography")
              .accessibilityAction { choose() }
              .background(
                browser.selectedOrthography?.id == orthography.id
                  ? WorkbenchStyle.accent.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 5)
              )
              .accessibilityIdentifier("Language orthography \(orthography.id)")
              .id(orthography.id)
          }
          if let orthography = browser.selectedOrthography {
            inventory(language, orthography: orthography)
          } else {
            Text("This language's orthographies are hidden. Clear filters to see them.")
              .foregroundStyle(.secondary)
          }
          ForEach([Side.a, .b], id: \.self) { side in
            if comparison[side] != nil {
              Text(
                verbatim:
                  "\(side == .a ? "A" : "B"): \(explanation(language, coverage: (side == .a ? browser.a : browser.b)[language.id]))"
              )
              .font(.caption).foregroundStyle(.secondary)
            }
          }
        } else {
          Text("Select a language to inspect its orthographies.").foregroundStyle(.secondary)
            .accessibilityLabel("Select a language to inspect its orthographies.")
            .accessibilityIdentifier("Language selection hint")
        }
      }.scrollTargetLayout().padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .scrollAreaIdentifier(
          "Language detail scroll area")
    }.scrollPosition(id: $browser.detailScrollID, anchor: .top)
  }

  private func sources(_ language: LanguageRecord) -> some View {
    LanguageDisclosure(
      "Sources and notes", identifier: "Language sources disclosure",
      isExpanded: expansion("\(language.id)/sources")
    ) {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(
          Array(
            (language.notes + language.sources + (browser.selectedOrthography?.notes ?? []))
              .enumerated()), id: \.offset
        ) { index, note in
          Text(verbatim: note).textSelection(.enabled).accessibilityIdentifier(
            "Language source note \(index)")
        }
        Text(
          verbatim:
            "Contributors: \(language.contributors.joined(separator: ", "))\nReviewers: \(language.reviewers.joined(separator: ", "))"
        ).accessibilityIdentifier("Language contributors text")
        Link(
          "Hyperglot 0.8.1", destination: URL(string: "https://github.com/rosettatype/hyperglot")!
        )
        .accessibilityIdentifier("Language source link")
      }.font(.caption)
    }.id("\(language.id)/sources")
  }

  private func expansion(_ id: String) -> Binding<Bool> {
    Binding(
      get: { browser.expanded.contains(id) },
      set: { enabled in
        if enabled { browser.expanded.insert(id) } else { browser.expanded.remove(id) }
      })
  }

  private func explanation(_ language: LanguageRecord, coverage: LanguageCoverage?) -> String {
    guard let coverage else { return "Checking" }
    if !coverage.available { return "Font unavailable" }
    let scripts = coverage.completeScripts(language)
    return scripts.isEmpty
      ? "No complete primary orthography." : "Complete through \(scripts.joined(separator: ", "))."
  }

  private func summary(
    _ language: LanguageRecord, orthography: OrthographyRecord, category: LanguageCategory
  ) -> String {
    [Side.a, .b].compactMap { side in
      guard comparison[side] != nil else { return nil }
      let label = side == .a ? "A" : "B"
      guard let coverage = (side == .a ? browser.a : browser.b)[language.id] else {
        return "\(label): Checking"
      }
      if !coverage.available { return "\(label): Font unavailable" }
      let inventory = coverage.orthographies[orthography.id]!.categories[category]!
      return
        "\(label): \(inventory.complete ? "Complete" : "Incomplete") · \(inventory.covered)/\(inventory.required) · \(inventory.missing.count) missing"
    }.joined(separator: "   ")
  }

  private func inventory(_ language: LanguageRecord, orthography: OrthographyRecord) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Character sheet").font(.headline)
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)], alignment: .leading
      ) {
        ForEach(LanguageCategory.allCases, id: \.self) { category in
          Toggle(
            category.rawValue.capitalized,
            isOn: Binding(
              get: { browser.categories.contains(category) },
              set: { enabled in
                if enabled {
                  browser.categories.insert(category)
                } else {
                  browser.categories.remove(category)
                }
              })
          ).toggleStyle(.checkbox).accessibilityIdentifier(
            "Language specimen \(category.rawValue) toggle")
        }
      }
      HStack {
        ForEach([Side.a, .b], id: \.self) { side in
          if let config = comparison[side] {
            VStack(alignment: .leading) {
              Text(verbatim: "Font \(side == .a ? "A" : "B") preview").font(.caption)
              FontPreviewText(
                config: config, text: orthography[.base].tokens.prefix(12).joined(separator: " ")
              ).frame(height: 34)
                .accessibilityIdentifier("Language \(side == .a ? "A" : "B") preview")
            }.frame(maxWidth: .infinity)
          }
        }
      }
      Button("Use as specimen") {
        useSpecimen(LanguageSpecimen.text(orthography, categories: browser.categories))
      }
      .disabled(LanguageSpecimen.text(orthography, categories: browser.categories).isEmpty)
      .accessibilityIdentifier("Language use specimen button")
      ForEach(LanguageCategory.allCases, id: \.self) { category in
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: category.rawValue.capitalized).font(.subheadline)
          Text(verbatim: summary(language, orthography: orthography, category: category)).font(
            .caption
          ).foregroundStyle(.secondary)
          LanguageDisclosure(
            "Missing \(category.rawValue) characters",
            identifier: "Language missing \(category.rawValue) disclosure",
            isExpanded: expansion("\(orthography.id)/\(category.rawValue)")
          ) {
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading
            ) {
              ForEach(missing(language, orthography: orthography, category: category)) {
                requirement in
                ForEach(Array(requirement.text.map(String.init).enumerated()), id: \.offset) {
                  index, glyph in
                  Button {
                    inspect(glyph)
                  } label: {
                    Text(verbatim: unicodeDescription(glyph)).font(.caption).lineLimit(2)
                  }.accessibilityLabel("Inspect language \(unicodeDescription(glyph))")
                    .accessibilityIdentifier(
                      "Language missing \(orthography.id) \(category.rawValue) \(requirement.scalars.map { String($0.value, radix: 16) }.joined(separator: "-")) \(requirement.sequence) \(index)"
                    )
                }
              }
            }
          }.font(.caption)
        }.id("\(orthography.id)/\(category.rawValue)")
      }
    }.scrollTargetLayout()
  }

  private func missing(
    _ language: LanguageRecord, orthography: OrthographyRecord, category: LanguageCategory
  ) -> [LanguageRequirement] {
    let requirements = [browser.a, browser.b].flatMap {
      $0[language.id]?.orthographies[orthography.id]?.categories[category]?.missing ?? []
    }
    var seen: Set<LanguageRequirement> = []
    return requirements.filter { seen.insert($0).inserted }
  }
}

private struct LanguageDisclosure<Content: View>: View {
  let title: String
  let identifier: String
  @Binding var isExpanded: Bool
  let content: Content

  init(
    _ title: String, identifier: String, isExpanded: Binding<Bool>,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.identifier = identifier
    _isExpanded = isExpanded
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      let toggle = { isExpanded.toggle() }
      Button(action: toggle) {
        HStack(spacing: 6) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
          Text(verbatim: title)
        }
      }.buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier(identifier)
        .accessibilityAction { toggle() }
      if isExpanded { content.padding(.leading, 16) }
    }
  }
}
