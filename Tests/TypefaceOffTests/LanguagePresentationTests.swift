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

@Suite(.serialized) @MainActor struct LanguagePresentationTests {
  @Test(arguments: [960.0, 1120, 1440])
  func tableAndSheetsShareColumnsAndKeepAllFiltersReachable(width: Double) async throws {
    let model = WorkbenchModel()
    model.updatePresentation { $0.mode = .languages }
    model.languages.selection = "eng"
    await model.languages.update(.init(model.comparison))
    let host = WorkbenchTestHost(WorkbenchView(model: model), width: width, height: 900)
    defer { host.window.close() }
    try await host.settle()
    let table = try #require(host.subviews.compactMap { $0 as? NSTableView }.first)
    #expect(table.rowHeight == 28 && table.numberOfRows == 108)
    #expect(abs(table.convert(table.rect(ofColumn: 3), to: host.view).midX - (width / 2 - 104)) < 1)
    #expect(table.rect(ofColumn: 4).maxX <= table.enclosingScrollView!.contentSize.width + 1)
    #expect(table.enclosingScrollView!.contentView.bounds.minY <= table.rect(ofRow: 0).minY)
    #expect(model.languages.rows.first?.speakers == 920_000_000)
    #expect(table.tableColumns.count == 5 && !table.tableColumns.last!.isHidden)
    let sheets = host.subviews.compactMap { $0 as? LanguageCharacterSheetView }
    #expect(sheets.count == 5)
    let base = try #require(sheets.first)
    #expect(base.lines.count == 2 && base.lines[0].count == base.lines[1].count)
    #expect(sheets[3].lines[0].count == 44)
    #expect(base.visibleRect.width >= Double(base.columns * 22 + 24))
    #expect(base.columns == (width == 1440 ? 28 : width == 1120 ? 20 : 17))
    for id in [
      "Language speaker field", "Language speaker slider", "Language coverage picker",
      "Language historical toggle", "Language clear filters button",
    ] {
      _ = try await host.element(id)
    }
    try capture(host, name: "languages-\(Int(width))")
    let coordinator = try #require(table.delegate as? LanguageTable.Coordinator)
    for column in table.tableColumns {
      coordinator.tableView(table, didClick: column)
      try await host.settle()
    }
    #expect(model.languages.ordering.column == .b)
    try await host.press("Language row eng", in: "Language list scroll area")
    #expect(model.languages.selection == "eng")
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try await host.settle()
    #expect(model.languages.selection == model.languages.rows.first?.id)
    table.deselectAll(nil)
    try await host.settle()
    #expect(model.languages.selection == nil)
    model.languages.selection = "eng"
    model.languages.filter.query = "English"
    try await host.settle()
    model.updatePresentation { $0.b = nil }
    try await host.settle { !model.languages.checking && model.languages.b.isEmpty }
    #expect(table.tableColumns.last!.isHidden)
    #expect(host.subviews.compactMap { $0 as? LanguageCharacterSheetView }.first?.lines.count == 1)
    if width == 1440 { try capture(host, name: "languages-single") }
  }

  @Test func scriptSelectionAndSourcesSurviveModeChanges() async throws {
    let model = WorkbenchModel()
    model.languages.selection = "srp"
    model.languages.filter.query = "Serbian"
    model.languages.filter.minimumSpeakers = 0
    model.updatePresentation { $0.mode = .languages }
    await model.languages.update(.init(model.comparison))
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    let language = try #require(model.languages.selectedLanguage)
    let scripts = language.orthographies(showHistorical: false)
    try #require(scripts.count > 1)
    let selected = scripts[1]
    try await host.choose(
      "Language script picker", nativeTitles: scripts.map(LanguagePresentation.script),
      item: LanguagePresentation.script(selected))
    #expect(model.languages.selectedOrthography?.id == selected.id)
    try await host.press("Language sources disclosure", in: "Language detail scroll area")
    #expect(model.languages.expanded.contains("srp/sources"))
    model.updatePresentation { $0.mode = .text }
    try await host.settle()
    model.updatePresentation { $0.mode = .languages }
    try await host.settle()
    #expect(model.languages.selectedOrthography?.id == selected.id)
    #expect(model.languages.expanded.contains("srp/sources"))
    try capture(host, name: "languages-scripts")
  }

  @Test func tableScrollAndKeyboardSelectionSurviveModeChanges() async throws {
    let model = WorkbenchModel()
    model.updatePresentation { $0.mode = .languages }
    await model.languages.update(.init(model.comparison))
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    let table = try #require(host.subviews.compactMap { $0 as? NSTableView }.first)
    let scroll = try #require(table.enclosingScrollView)
    let id = model.languages.rows[40].id
    scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 40).minY))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await host.settle()
    #expect(model.languages.scrollID == id)
    model.updatePresentation { $0.mode = .text }
    try await host.settle()
    model.updatePresentation { $0.mode = .languages }
    try await host.settle()
    let restored = try #require(host.subviews.compactMap { $0 as? NSTableView }.first)
    #expect(restored.row(at: restored.enclosingScrollView!.contentView.bounds.origin) == 40)
    restored.selectRowIndexes(IndexSet(integer: 40), byExtendingSelection: false)
    try await host.settle()
    host.window.makeFirstResponder(restored)
    host.window.sendEvent(
      try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero,
          modifierFlags: [], timestamp: 0, windowNumber: host.window.windowNumber, context: nil,
          characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false,
          keyCode: 125)))
    try await host.settle()
    #expect(model.languages.selection == model.languages.rows[41].id)
    model.updatePresentation { $0.b = .init("Missing-Language-Font") }
    try await host.settle { !model.languages.checking }
    try capture(host, name: "languages-missing-font")
  }

  @Test func sheetNeverDrawsFallbackAndKeepsScalarDistinctTokens() throws {
    let view = LanguageCharacterSheetView(frame: NSRect(x: 0, y: 0, width: 220, height: 110))
    view.draw(.zero)
    let tokens = ["A", "é", "e\u{301}", "\u{FFFF}"]
    let comparison = Comparison(a: .init("ArialMT"), b: .init("Missing-Language-Font"))
    view.update(tokens: tokens, comparison: comparison, columns: 2)
    #expect(view.lines[0][0] != nil && view.lines[0][3] == nil)
    #expect(view.lines[1].allSatisfy { $0 == nil })
    try draw(view)
    view.update(tokens: tokens, comparison: comparison, columns: 4)
    try draw(view)
    view.update(tokens: ["e\u{301}"], comparison: Comparison(b: nil), columns: 4)
    #expect(view.lines.count == 1 && view.lines[0].count == 1)
    try draw(view)
    for mark in [LanguageCoverageMark.checking, .unavailable, .incomplete, .complete] {
      let cell = LanguageTableCell(frame: NSRect(x: 0, y: 0, width: 48, height: 28))
      cell.mark = mark
      #expect(!cell.accessibilityPerformPress())
      try draw(cell)
    }
  }

  private func draw(_ view: NSView) throws {
    let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: image)
  }

  private func capture<Content>(_ host: WorkbenchTestHost<Content>, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] else {
      return
    }
    let image = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: image)
    try #require(image.representation(using: .png, properties: [:])).write(
      to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
  }
}
