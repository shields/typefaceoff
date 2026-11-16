import AppKit
import SwiftUI
import TypefaceCore

struct LanguageBrowserView: View {
  @ObservedObject var browser: LanguageBrowserModel
  let comparison: Comparison
  let inspect: (String) -> Void
  let useSpecimen: (String) -> Void
  var body: some View {
    GeometryReader { geometry in
      let column = max(384, (geometry.size.width - 192) / 2)
      VStack(spacing: 0) {
        LanguageFilters(browser: browser, comparing: comparison.b != nil)
        if let problem = browser.problem {
          Text(verbatim: "⚠︎ Language coverage failed: \(problem)")
            .foregroundStyle(WorkbenchStyle.ink).padding()
            .accessibilityLabel(Text(verbatim: "Language coverage failed: \(problem)"))
            .accessibilityIdentifier("Language coverage error message")
        }
        browserContent(column: column)
      }
    }
  }

  @ViewBuilder private func browserContent(column: Double) -> some View {
    if browser.database != nil {
      HStack(alignment: .top, spacing: 64) {
        languageList.frame(width: column + 24)
        LanguageDetail(
          browser: browser, comparison: comparison, width: column,
          inspect: inspect, useSpecimen: useSpecimen
        ).frame(width: column)
      }.padding(.leading, 40).padding(.trailing, 64)
    } else if browser.problem == nil {
      ProgressView("Loading languages").frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var languageList: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Spacer()
        Circle().fill(WorkbenchStyle.ink).frame(width: 9, height: 9)
        Text("Complete")
        Circle().stroke(WorkbenchStyle.secondaryInk, lineWidth: 1.5)
          .frame(width: 9, height: 9).padding(.leading, 8)
        Text("Incomplete")
      }.font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
        .frame(height: 38)
      if !browser.filter.query.isEmpty && browser.hiddenMatches > 0 {
        Text(
          verbatim:
            "\(browser.hiddenMatches) matching languages are hidden by the speaker or historical filters."
        )
        .font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
        .padding(.leading, 24)
      }
      LanguageTable(browser: browser, comparison: comparison)
        .padding(.trailing, -NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
        .overlay(alignment: .topLeading) {
          if browser.rows.isEmpty {
            Text("No languages match these filters.")
              .foregroundStyle(WorkbenchStyle.secondaryInk).padding(.top, 40).padding(.leading, 24)
              .accessibilityLabel("No languages match these filters.")
              .accessibilityIdentifier("Language empty list message")
          }
        }
    }
  }

}
