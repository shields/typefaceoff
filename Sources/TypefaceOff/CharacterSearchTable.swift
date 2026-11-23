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

struct CharacterSearchTable: NSViewRepresentable {
  let results: [CharacterSearchResult]
  let fonts: [FontConfiguration]
  @Binding var selection: [Unicode.Scalar]?
  let spacingOnly: Bool
  let choose: (String) -> Void
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
    table.addTableColumn(NSTableColumn(identifier: .init("Character")))
    table.autoresizingMask = [.width]
    table.headerView = nil
    table.rowHeight = 48
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
    coordinator.environment = context.environment
    coordinator.updating = true
    defer { coordinator.updating = false }
    table.confirm = confirm
    table.cancel = cancel
    let origin = scroll.contentView.bounds.origin
    table.reloadData()
    if let row = results.firstIndex(where: { $0.id == selection }) {
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
    var parent: CharacterSearchTable
    var selection: [Unicode.Scalar]?
    var environment = EnvironmentValues()
    var updating = false

    init(_ parent: CharacterSearchTable) { self.parent = parent }

    func numberOfRows(in tableView: NSTableView) -> Int { parent.results.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
      guard !updating else { return }
      let table = notification.object as! NSTableView
      let selection = table.selectedRow < 0 ? nil : parent.results[table.selectedRow].id
      Task { @MainActor in self.parent.selection = selection }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
      PickerSelectionRow()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      let result = parent.results[row]
      let names = CharacterSearchRow.names(of: parent.fonts)
      return NSHostingView(
        rootView: Button {
          self.parent.choose(result.glyph)
        } label: {
          CharacterSearchRow(
            result: result, fonts: parent.fonts, names: names, spacingOnly: parent.spacingOnly
          ).padding(.horizontal, 8)
        }.buttonStyle(.plain).foregroundStyle(WorkbenchStyle.ink)
          .accessibilityLabel(Text(verbatim: CharacterSearchRow.label(result, names: names)))
          .environment(\.self, environment)
          .preferredColorScheme(.light))
    }
  }
}
