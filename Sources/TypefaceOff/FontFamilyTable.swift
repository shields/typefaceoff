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

struct FontFamilyTable: NSViewRepresentable {
  let choices: [FontFamilyPicker.Choice]
  let currentFamily: String?
  @Binding var selection: FontFamilyPicker.Choice?
  let similarity: [String: FamilySimilarity]?
  let catalog: FontCatalog
  let choose: (String?) -> Void
  let confirm: () -> Void
  let cancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = true
    scroll.backgroundColor = NSColor(WorkbenchStyle.paper)
    let table = PickerTableView()
    table.addTableColumn(NSTableColumn(identifier: .init("Family")))
    table.autoresizingMask = [.width]
    table.headerView = nil
    table.rowHeight = 30
    table.intercellSpacing = .zero
    table.backgroundColor = NSColor(WorkbenchStyle.paper)
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.allowsEmptySelection = true
    table.delegate = context.coordinator
    table.dataSource = context.coordinator
    scroll.documentView = table
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let table = scroll.documentView as! PickerTableView
    let coordinator = context.coordinator
    let oldSelection = coordinator.selection
    coordinator.parent = self
    coordinator.selection = selection
    coordinator.updating = true
    defer { coordinator.updating = false }
    table.confirm = confirm
    table.cancel = cancel
    let origin = scroll.contentView.bounds.origin
    table.reloadData()
    if let selection, let row = choices.firstIndex(of: selection) {
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      if oldSelection != selection {
        table.scrollRowToVisible(row)
        return
      }
    } else {
      table.deselectAll(nil)
    }
    scroll.contentView.scroll(to: origin)
  }

  @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: FontFamilyTable
    var selection: FontFamilyPicker.Choice?
    var updating = false
    private var fonts: [String: NSFont] = [:]

    init(_ parent: FontFamilyTable) { self.parent = parent }

    func numberOfRows(in tableView: NSTableView) -> Int { parent.choices.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
      guard !updating else { return }
      let table = notification.object as! NSTableView
      let choice = table.selectedRow < 0 ? nil : parent.choices[table.selectedRow]
      Task { @MainActor in self.parent.selection = choice }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
      PickerSelectionRow()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      let choice = parent.choices[row]
      let button = FontFamilyRowButton()
      button.title = choice.title
      button.isBordered = false
      button.font = font(for: choice)
      button.current = choice.family == parent.currentFamily
      button.setAccessibilityLabel(choice.title)
      if let similarity = parent.similarity, let family = choice.family {
        if let result = similarity[family] {
          button.distance = result.score?.formattedDistance ?? "Unavailable"
          button.toolTip = result.unavailableReason ?? "Heuristic distance; lower is closer"
        } else {
          button.distance = "Pending"
        }
      }
      button.setAccessibilityValue(
        ([button.current ? "Current font" : nil, button.distance].compactMap { $0 }).joined(
          separator: ", "))
      button.choose = { self.parent.choose(choice.family) }
      button.target = button
      button.action = #selector(FontFamilyRowButton.chooseFamily)
      return button
    }

    private func font(for choice: FontFamilyPicker.Choice) -> NSFont {
      if let cached = fonts[choice.title] { return cached }
      var font = NSFont.systemFont(ofSize: 15)
      if let family = choice.family, let face = parent.catalog.preferredFace(in: family) {
        var config = FontConfiguration(face.id)
        config.size = 15
        if FontRenderer.supports(family, config: config) {
          font = FontRenderer.font(config) as NSFont
        }
      }
      fonts[choice.title] = font
      return font
    }
  }
}

final class FontFamilyRowButton: NSButton {
  var current = false
  var distance: String?
  var choose: (() -> Void)?

  @objc func chooseFamily() { choose!() }

  override func draw(_ dirtyRect: NSRect) {
    let ink = NSColor(WorkbenchStyle.ink)
    if current {
      ("✓" as NSString).draw(
        at: NSPoint(x: 7, y: 7),
        withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink])
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingMiddle
    (title as NSString).draw(
      in: NSRect(
        x: 26, y: 5, width: max(0, bounds.width - (distance == nil ? 34 : 112)), height: 24),
      withAttributes: [.font: font!, .foregroundColor: ink, .paragraphStyle: paragraph])
    if let distance {
      paragraph.alignment = .right
      (distance as NSString).draw(
        in: NSRect(x: bounds.width - 78, y: 8, width: 78, height: 18),
        withAttributes: [
          .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
          .foregroundColor: NSColor(WorkbenchStyle.secondaryInk), .paragraphStyle: paragraph,
        ])
    }
  }
}
