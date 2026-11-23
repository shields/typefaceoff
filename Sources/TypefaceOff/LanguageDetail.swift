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

import AppKit
import SwiftUI
import TypefaceCore

struct LanguageDetail: View {
  @ObservedObject var browser: LanguageBrowserModel
  let comparison: Comparison
  let width: Double
  let inspect: (String) -> Void
  let useSpecimen: (String) -> Void

  var body: some View {
    if let language = browser.selectedLanguage,
      !language.historical || browser.filter.showHistorical
    {
      VStack(spacing: 0) {
        header(language)
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if let orthography = browser.selectedOrthography {
              ForEach(LanguageCategory.allCases, id: \.self) { category in
                band(language, orthography: orthography, category: category)
                  .id("\(orthography.id)/\(category.rawValue)")
              }
            } else {
              Text("This language's orthographies are hidden. Clear filters to see them.")
                .foregroundStyle(WorkbenchStyle.secondaryInk).padding(.vertical, 12)
            }
            footer(language).padding(.top, 8)
          }.scrollTargetLayout().padding(.leading, 24).padding(.bottom, 16)
            .scrollAreaIdentifier("Language detail scroll area")
        }.scrollPosition(id: $browser.detailScrollID, anchor: .top)
          .padding(.leading, -24)
          .padding(.trailing, -NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
      }
    } else {
      Text("Select a language to inspect its orthographies.")
        .foregroundStyle(WorkbenchStyle.secondaryInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 16)
        .accessibilityLabel("Select a language to inspect its orthographies.")
        .accessibilityIdentifier("Language selection hint")
    }
  }

  private func header(_ language: LanguageRecord) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: language.name).font(.system(size: 20, weight: .semibold))
          .lineLimit(1).help(language.name)
        Spacer(minLength: 0)
        Button("Use Checked as Specimen") {
          useSpecimen(specimen)
        }.disabled(specimen.isEmpty).accessibilityIdentifier("Language use specimen button")
          .fixedSize()
      }.frame(height: 30)
      HStack(spacing: 8) {
        Text(verbatim: LanguagePresentation.facts(language)).font(.system(size: 11))
          .foregroundStyle(WorkbenchStyle.secondaryInk).lineLimit(1)
          .help(LanguagePresentation.facts(language)).textSelection(.enabled)
        Spacer(minLength: 0)
        script(language)
      }.frame(height: 24)
      WorkbenchStyle.hairline.frame(height: 1)
    }.padding(.top, 8)
  }

  private var specimen: String {
    browser.selectedOrthography.map { LanguageSpecimen.text($0, categories: browser.categories) }
      ?? ""
  }

  @ViewBuilder private func script(_ language: LanguageRecord) -> some View {
    let orthographies = language.orthographies(showHistorical: browser.filter.showHistorical)
    if orthographies.count > 1 {
      Picker(
        "Language script",
        selection: Binding(
          get: { browser.selectedOrthography!.id },
          set: { browser.orthographySelection = $0 }
        )
      ) {
        ForEach(orthographies) { orthography in
          Text(verbatim: LanguagePresentation.script(orthography)).tag(orthography.id)
        }
      }.labelsHidden().pickerStyle(.menu).accessibilityIdentifier("Language script picker")
        .fixedSize()
    } else if let orthography = orthographies.first {
      Text(verbatim: LanguagePresentation.script(orthography)).font(.system(size: 11)).fixedSize()
    }
  }

  private func band(
    _ language: LanguageRecord, orthography: OrthographyRecord, category: LanguageCategory
  )
    -> some View
  {
    let sheet = LanguageCharacterSheet(
      tokens: LanguagePresentation.cells(orthography[category]), comparison: comparison,
      columns: max(1, min(width >= 616 ? 28 : 20, Int(width / 22))),
      summary: sheetSummary(language, orthography: orthography, category: category))
    let missing = missing(language, orthography: orthography, category: category)
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 12) {
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
            }
          )
        ).toggleStyle(.checkbox).fontWeight(.semibold)
          .accessibilityIdentifier("Language specimen \(category.rawValue) toggle")
          .frame(width: width >= 616 ? 148 : 116, alignment: .leading)
        ForEach([Side.a, .b], id: \.self) { side in
          if comparison[side] != nil {
            HStack(spacing: 6) {
              Text(verbatim: side == .a ? "A" : "B").fontWeight(.bold)
                .foregroundStyle(
                  FontRenderer.isAvailable(comparison[side]!)
                    ? Color(side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue)
                    : WorkbenchStyle.secondaryInk)
              let status = count(language, orthography: orthography, category: category, side: side)
              Text(verbatim: status == "Font unavailable" ? "—" : status)
                .accessibilityLabel(Text(verbatim: status))
                .foregroundStyle(WorkbenchStyle.secondaryInk)
            }.font(.system(size: 13)).monospacedDigit()
              .frame(width: width >= 616 ? 76 : 64, alignment: .leading)
          }
        }
        if !missing.isEmpty {
          ScrollView(.horizontal) {
            LazyHStack(spacing: 4) {
              ForEach(
                missing.flatMap { requirement in
                  requirement.text.map(String.init).enumerated().map { index, glyph in
                    (
                      id:
                        "Language missing \(orthography.id) \(category.rawValue) \(requirement.scalars.map { String($0.value, radix: 16) }.joined(separator: "-")) \(requirement.sequence) \(index)",
                      glyph: glyph
                    )
                  }
                }, id: \.id
              ) { item in
                Button {
                  inspect(item.glyph)
                } label: {
                  Text(verbatim: item.glyph).frame(minWidth: 24, minHeight: 24)
                }.buttonStyle(.plain)
                  .help(unicodeDescription(item.glyph))
                  .accessibilityLabel("Inspect language \(unicodeDescription(item.glyph))")
                  .accessibilityIdentifier(item.id)
              }
            }.scrollAreaIdentifier("Language \(category.rawValue) missing scroll area")
          }.frame(height: 24)
        } else {
          Spacer(minLength: 0)
        }
      }.frame(minHeight: 24)
      sheet.frame(height: sheet.height).padding(.leading, -24)
      WorkbenchStyle.hairline.frame(height: 1).padding(.top, 4)
    }.padding(.top, 4)
  }

  private func count(
    _ language: LanguageRecord, orthography: OrthographyRecord,
    category: LanguageCategory, side: Side
  ) -> String {
    guard let coverage = (side == .a ? browser.a : browser.b)[language.id] else {
      return "Checking"
    }
    guard coverage.available else { return "Font unavailable" }
    let inventory = coverage.orthographies[orthography.id]!.categories[category]!
    return "\(inventory.covered)/\(inventory.required)"
  }

  private func sheetSummary(
    _ language: LanguageRecord, orthography: OrthographyRecord,
    category: LanguageCategory
  ) -> String {
    category.rawValue.capitalized + ": "
      + [Side.a, .b].compactMap { side in
        guard comparison[side] != nil else { return nil }
        let status = count(language, orthography: orthography, category: category, side: side)
        let description =
          status.contains("/")
          ? status.replacingOccurrences(of: "/", with: " of ") + " present" : status
        return "Font \(side == .a ? "A" : "B"), \(description)"
      }.joined(separator: "; ")
  }

  private func missing(
    _ language: LanguageRecord, orthography: OrthographyRecord,
    category: LanguageCategory
  ) -> [LanguageRequirement] {
    let requirements = [browser.a, browser.b].flatMap {
      $0[language.id]?.orthographies[orthography.id]?.categories[category]?.missing ?? []
    }
    var seen: Set<LanguageRequirement> = []
    return requirements.filter { seen.insert($0).inserted }
  }

  private func footer(_ language: LanguageRecord) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Text("Character coverage does not assess joining, mark placement, or visual quality.")
          .font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
        if hasMissing(language) {
          HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).stroke(
              WorkbenchStyle.track, style: StrokeStyle(lineWidth: 1, dash: [1.5, 2])
            )
            .frame(width: 18, height: 18)
            Text("Missing").font(.system(size: 11))
          }.fixedSize()
        }
      }
      let id = "\(language.id)/sources"
      Button {
        if browser.expanded.contains(id) {
          browser.expanded.remove(id)
        } else {
          browser.expanded.insert(id)
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: browser.expanded.contains(id) ? "chevron.down" : "chevron.right")
          Text("Sources and notes")
        }.frame(minHeight: 24)
      }.buttonStyle(.plain).accessibilityIdentifier("Language sources disclosure")
        .accessibilityValue(browser.expanded.contains(id) ? "Expanded" : "Collapsed")
      if browser.expanded.contains(id) {
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
          )
          .accessibilityIdentifier("Language contributors text")
          Link(
            "Hyperglot 0.8.1", destination: URL(string: "https://github.com/rosettatype/hyperglot")!
          )
          .accessibilityIdentifier("Language source link")
        }.font(.system(size: 11)).padding(.leading, 16)
      }
    }.id("\(language.id)/sources")
  }

  private func hasMissing(_ language: LanguageRecord) -> Bool {
    guard let orthography = browser.selectedOrthography else { return false }
    return LanguageCategory.allCases.contains {
      !missing(language, orthography: orthography, category: $0).isEmpty
    }
  }
}
