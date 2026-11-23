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
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct LanguageBrowserTests {
  @Test func filteringKeepsScoresAndWindowStateIndependent() async {
    let browser = LanguageBrowserModel()
    let other = LanguageBrowserModel()
    let request = LanguageBrowserModel.Request(Comparison())
    #expect(
      browser.rows.isEmpty && browser.selectedLanguage == nil && browser.selectedOrthography == nil)
    #expect(browser.hiddenMatches == 0)
    await browser.update(request)
    #expect(!browser.checking && browser.problem == nil)
    #expect(browser.a.count == 705 && browser.b.count == 705)
    #expect(browser.comparing && browser.rows.count == 108)
    #expect(browser.maximumSpeakers == 920_000_000)
    browser.selection = "eng"
    browser.orthographySelection = browser.selectedOrthography?.id
    browser.scrollID = "eng"
    browser.filter.query = "English"
    #expect(browser.rows.map(\.id) == ["eng"])
    #expect(browser.selectedLanguage?.name == "English")
    #expect(browser.selectedOrthography?.script == "Latin")
    #expect(browser.hiddenMatches == 1)
    browser.filter.query = "Latin"
    #expect(browser.hiddenMatches > 0)
    browser.clearFilters()
    #expect(browser.filter.showHistorical && browser.filter.minimumSpeakers == 0)
    #expect(browser.a.count == 705)
    #expect(other.filter.minimumSpeakers == 8_300_000 && other.selection == nil)
    await browser.update(request)
    #expect(browser.selection == "eng" && browser.scrollID == "eng")
    browser.coverageFilter = .bOnly
    await browser.update(LanguageBrowserModel.Request(Comparison(b: nil)))
    #expect(!browser.comparing && browser.b.isEmpty && browser.coverageFilter == .all)
    browser.coverageFilter = .covered
    #expect(browser.rows.allSatisfy { browser.a[$0.id]?.complete($0) == true })
  }

  @Test(arguments: [false, true])
  func obsoleteLoadsCannotPublish(cancel: Bool) async {
    let (starts, continuation) = AsyncStream<Int>.makeStream()
    let loader = SuspendedLanguages(started: continuation)
    let browser = LanguageBrowserModel(load: { await loader.load() })
    var iterator = starts.makeAsyncIterator()
    let old = Task { await browser.update(LanguageBrowserModel.Request(Comparison())) }
    #expect(await iterator.next() == 0)
    let newest = Task { await browser.update(LanguageBrowserModel.Request(Comparison(b: nil))) }
    #expect(await iterator.next() == 1)
    if cancel { old.cancel() }
    await loader.finish(1)
    await newest.value
    await loader.finish(0)
    await old.value
    #expect(browser.b.isEmpty && browser.a.count == 705 && !browser.checking)
    let cancelled = LanguageBrowserModel(load: { throw CancellationError() })
    await cancelled.update(LanguageBrowserModel.Request(Comparison()))
    #expect(cancelled.problem == nil && !cancelled.checking)
  }

  enum LoadState: CaseIterable, Sendable { case loading, failed, ready }

  @Test(arguments: LoadState.allCases)
  func errorsAndLoadingAreVisible(state: LoadState) async throws {
    let browser = LanguageBrowserModel(load: {
      if state == .failed { throw LanguageTestError() }
      return LanguageDatabase.shared
    })
    if state != .loading { await browser.update(.init(Comparison())) }
    let host = WorkbenchTestHost(
      LanguageBrowserView(
        browser: browser, comparison: Comparison(), inspect: { _ in }, useSpecimen: { _ in }),
      width: 960, height: 700)
    defer { host.window.close() }
    try await host.settle()
    switch state {
    case .loading:
      _ = try await host.element("Loading languages")
      #expect(browser.database == nil && browser.problem == nil)
    case .failed:
      _ = try await host.element("Language coverage error message")
      #expect(browser.database == nil && browser.problem == "Expected language failure")
    case .ready:
      let languages = Array(browser.rows.prefix(3))
      try #require(languages.count == 3)
      for language in languages {
        browser.filter.query = language.name
        try await host.settle()
        _ = try await host.element("Language row \(language.id)")
      }
      #expect(browser.database != nil && browser.problem == nil && !browser.checking)
    }
  }

  @Test func historicalOnlyOrthographiesAndEmptySheetsStayExplicit() async throws {
    let data = Data(
      #"""
      {"schema":1,"version":"fixture","source":"fixture","excluded":{},"languages":[
        {"id":"ui-history-fixture","name":"Example","isoName":"Example","status":"living",
         "validity":"preliminary","speakers":null,"speakersDate":null,"autonyms":[],
         "notes":["Example note"],"sources":[],"contributors":[],"reviewers":[],
         "orthographies":[{"id":"ui-history-fixture/old","script":"Latin","scriptCode":"Latn",
           "status":"historical","autonym":"","grouped":true,"notes":[],"categories":{
             "base":{"characters":"\uFFFF","requirements":"\uFFFF","sequences":""},
             "auxiliary":{"characters":"","requirements":"","sequences":""},
             "numerals":{"characters":"","requirements":"","sequences":""},
             "punctuation":{"characters":"","requirements":"","sequences":""},
             "currency":{"characters":"","requirements":"","sequences":""}}}]}]}
      """#.utf8)
    let database = try LanguageDatabase.decode(data)
    let browser = LanguageBrowserModel(engine: LanguageCoverageEngine(), load: { database })
    browser.clearFilters()
    let comparison = Comparison(a: .init("ArialMT"), b: nil)
    await browser.update(.init(comparison))
    let host = WorkbenchTestHost(
      LanguageBrowserView(
        browser: browser, comparison: comparison, inspect: { _ in }, useSpecimen: { _ in }),
      width: 960, height: 850)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Language specimen base toggle")
    #expect(browser.categories.isEmpty)
    #expect(!host.isEnabled("Language use specimen button"))
    try await host.press("Language sources disclosure")
    #expect(browser.expanded.contains("ui-history-fixture/sources"))
    try await host.press("Language sources disclosure")
    #expect(!browser.expanded.contains("ui-history-fixture/sources"))
    browser.filter.showHistorical = false
    try await host.settle()
    #expect(browser.selectedOrthography == nil)
    #expect(browser.rows.isEmpty)
    try await host.press("Language sources disclosure", in: "Language detail scroll area")
  }

  @Test(arguments: [600.0, 900.0])
  func browserAppliesOneUndoableSpecimenAndRetainsBrowsing(height: Double) async throws {
    let model = WorkbenchModel()
    let fonts = model.comparison
    model.languages.selection = "eng"
    model.languages.filter.query = "English"
    model.updatePresentation { $0.mode = .languages }
    await model.languages.update(.init(model.comparison))
    #expect(model.languages.a.count == 705 && model.languages.b.count == 705)
    let host = WorkbenchTestHost(WorkbenchView(model: model), height: height)
    defer { host.window.close() }
    try await host.settle()
    model.languages.selection = nil
    try await host.settle()
    try await host.press("Language row eng")
    #expect(model.languages.selection == "eng")
    let orthography = try #require(model.languages.selectedOrthography)
    try await host.press("Language specimen numerals toggle", in: "Language detail scroll area")
    try await host.press("Language specimen currency toggle", in: "Language detail scroll area")
    try await host.press("Language specimen auxiliary toggle", in: "Language detail scroll area")
    try await host.press("Language specimen auxiliary toggle", in: "Language detail scroll area")
    let expected = LanguageSpecimen.text(orthography, categories: model.languages.categories)
    let undo = try #require(host.window.undoManager)
    undo.beginUndoGrouping()
    try await host.press("Language use specimen button")
    undo.endUndoGrouping()
    try await host.settle { model.comparison.mode == .text }
    #expect(model.comparison.customText.unicodeScalars.elementsEqual(expected.unicodeScalars))
    #expect(model.comparison.sample == .custom)
    #expect(
      model.comparison.a == fonts.a && model.comparison.b == fonts.b
        && model.comparison.link == fonts.link)
    #expect(undo.undoActionName == "Use language specimen")
    model.updatePresentation { $0.mode = .languages }
    undo.undo()
    #expect(model.comparison.sample == fonts.sample && model.comparison.mode == .languages)
    #expect(model.languages.filter.query == "English" && model.languages.selection == "eng")
    try await host.settle()
    let previousThreshold = model.languages.filter.minimumSpeakers
    try await host.incrementSlider("Language speaker slider", title: "Minimum speaker count")
    try await host.settle()
    #expect(model.languages.filter.minimumSpeakers > previousThreshold)
    #expect(model.languages.a.count == 705 && model.languages.b.count == 705)
    let threshold = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first {
        $0.placeholderString == "Minimum speaker count"
      })
    try await host.submit("100k", to: threshold)
    #expect(model.languages.filter.minimumSpeakers == 100_000)
    try await host.submit("bad", to: threshold)
    #expect(model.languages.filter.minimumSpeakers == 100_000)
    try await host.submit("1B", to: threshold)
    #expect(model.languages.filter.minimumSpeakers == 100_000)
    try await host.submit("1000M", to: threshold)
    #expect(model.languages.filter.minimumSpeakers == 920_000_000)
    try await host.press("Language historical toggle")
    #expect(model.languages.filter.showHistorical)
    try await host.press("Language clear filters button")
    #expect(model.languages.filter.minimumSpeakers == 0)
    try await host.press("Language sources disclosure", in: "Language detail scroll area")
  }

  @Test func specimenEditsPreserveCanonicalVariantsThroughUndo() {
    var comparison = Comparison()
    comparison.sample = .custom
    comparison.customText = "é"
    comparison.mode = .languages
    let model = WorkbenchModel(comparison: comparison)
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    model.useLanguageSpecimen("e\u{301}", undoManager: undo)
    undo.endUndoGrouping()
    #expect(model.comparison.customText.unicodeScalars.elementsEqual("e\u{301}".unicodeScalars))
    #expect(model.specimenGlyphs == [Array("e\u{301}".unicodeScalars)])
    #expect(undo.canUndo)
    undo.undo()
    #expect(model.comparison.customText.unicodeScalars.elementsEqual("é".unicodeScalars))
    #expect(model.comparison.mode == .text)
    #expect(model.comparison.a == comparison.a && model.comparison.b == comparison.b)
  }

  @Test func missingCharactersOpenGlyphViewWithoutTruncatingSheets() async throws {
    var comparison = Comparison(a: .init("Missing-Language-Font"), b: nil)
    comparison.mode = .languages
    let model = WorkbenchModel(comparison: comparison)
    model.languages.selection = "eng"
    model.languages.filter.query = "zzzz"
    await model.languages.update(.init(comparison))
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle { !model.languages.checking && model.languages.database != nil }
    _ = try await host.element("Language empty list message")
    model.languages.filter.query = "English"
    try await host.settle()
    try await host.press("Inspect language \(unicodeDescription("A"))")
    #expect(model.comparison.mode == .glyph && model.comparison.matches("A"))
    model.languages.selection = nil
    model.updatePresentation { $0.mode = .languages }
    try await host.settle()
    _ = try await host.element("Language selection hint")
    model.languages.selection = "grc"
    try await host.settle()
    _ = try await host.element("Language selection hint")
    model.languages.filter.showHistorical = true
    model.languages.filter.query = "Ancient Greek"
    try await host.settle()
    try await host.press("Language row grc")
    #expect(model.languages.selectedLanguage?.historical == true)
  }
}

private struct LanguageTestError: LocalizedError {
  var errorDescription: String? { "Expected language failure" }
}

private actor SuspendedLanguages {
  let started: AsyncStream<Int>.Continuation
  private var next = 0
  private var pending: [Int: CheckedContinuation<LanguageDatabase, Never>] = [:]
  init(started: AsyncStream<Int>.Continuation) { self.started = started }
  func load() async -> LanguageDatabase {
    await withCheckedContinuation {
      pending[next] = $0
      started.yield(next)
      next += 1
    }
  }
  func finish(_ id: Int) {
    pending.removeValue(forKey: id)!.resume(returning: LanguageDatabase.shared)
  }
}
