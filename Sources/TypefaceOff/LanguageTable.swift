import AppKit
import SwiftUI
import TypefaceCore

struct LanguageTable: NSViewRepresentable {
  @ObservedObject var browser: LanguageBrowserModel
  let comparison: Comparison
  private var comparing: Bool { comparison.b != nil }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = LanguageTableScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.setAccessibilityIdentifier("Language list scroll area")
    let table = NSTableView()
    table.style = .plain
    table.autoresizingMask = [.width]
    table.backgroundColor = NSColor(WorkbenchStyle.paper)
    table.rowHeight = 28
    table.intercellSpacing = .zero
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.allowsEmptySelection = true
    table.allowsColumnReordering = false
    table.allowsColumnResizing = false
    table.delegate = context.coordinator
    table.dataSource = context.coordinator
    for title in ["Language", "Speakers", "", "A", "B"] {
      let column = NSTableColumn(identifier: .init(title))
      column.headerCell = LanguageHeaderCell(textCell: title)
      column.width = title == "Language" ? 424 : title == "Speakers" ? 96 : title.isEmpty ? 32 : 48
      column.minWidth = title == "Language" ? 100 : column.width
      column.maxWidth = title == "Language" ? 2000 : column.width
      table.addTableColumn(column)
    }
    table.headerView?.frame.size.height = 32
    scroll.documentView = table
    scroll.didScroll = context.coordinator.rememberScroll
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let table = scroll.documentView as! NSTableView
    let coordinator = context.coordinator
    let firstUpdate = coordinator.rows.isEmpty
    let oldSelection = coordinator.selection
    coordinator.parent = self
    coordinator.rows = browser.rows
    coordinator.selection = browser.selection
    coordinator.updating = true
    defer { coordinator.updating = false }
    table.tableColumns.last!.isHidden = !comparing
    for column in table.tableColumns {
      let header = column.headerCell as! LanguageHeaderCell
      header.ordered = column.identifier.rawValue == browser.ordering.column.rawValue
      header.ascending = browser.ordering.ascending
      let config = column.identifier.rawValue == "A" ? comparison.a : comparison.b
      header.available = config.map(FontRenderer.isAvailable) == true
    }
    table.headerView?.needsDisplay = true
    scroll.tile()
    let origin = scroll.contentView.bounds.origin
    table.reloadData()
    if let index = coordinator.rows.firstIndex(where: { $0.id == browser.selection }) {
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      if firstUpdate, let top = browser.scrollID,
        let index = coordinator.rows.firstIndex(where: { $0.id == top })
      {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: index).minY))
      } else if !firstUpdate && oldSelection != browser.selection {
        table.scrollRowToVisible(index)
      } else {
        scroll.contentView.scroll(to: origin)
      }
    } else {
      table.deselectAll(nil)
    }
  }

  @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: LanguageTable
    var rows: [LanguageRecord] = []
    var selection: String?
    var updating = false

    init(_ parent: LanguageTable) { self.parent = parent }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
      if let column = LanguageColumn(rawValue: tableColumn.identifier.rawValue) {
        parent.browser.ordering.select(column)
      }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
      guard !updating else { return }
      let table = notification.object as! NSTableView
      let id = table.selectedRow < 0 ? nil : rows[table.selectedRow].id
      Task { @MainActor in self.select(id) }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
      LanguageSelectionRow()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      let language = rows[row]
      let title = tableColumn!.identifier.rawValue
      let cell = LanguageTableCell()
      cell.title =
        title == "Language" ? language.name : LanguagePresentation.speakers(language.speakers)
      cell.column = title
      cell.current = language.id == parent.browser.selection
      cell.setAccessibilityElement(true)
      cell.setAccessibilityRole(.staticText)
      if title == "Language" {
        cell.setAccessibilityRole(.button)
        cell.setAccessibilityIdentifier("Language row \(language.id)")
        cell.setAccessibilityLabel("Browse \(language.name)")
        cell.choose = { self.select(language.id) }
        cell.toolTip = language.name
      } else if title == "A" || title == "B" {
        let coverage = title == "A" ? parent.browser.a : parent.browser.b
        cell.mark = LanguageCoverageMark(coverage[language.id], language: language)
        cell.setAccessibilityLabel("Font \(title) coverage")
        cell.setAccessibilityValue(cell.mark!.title)
      } else {
        cell.setAccessibilityValue(title.isEmpty ? "" : cell.title)
        cell.setAccessibilityElement(!title.isEmpty)
      }
      return cell
    }

    func rememberScroll(_ scroll: NSScrollView) {
      guard !updating else { return }
      let table = scroll.documentView as! NSTableView
      let row = table.row(at: scroll.contentView.bounds.origin)
      guard rows.indices.contains(row) else { return }
      let id = rows[row].id
      if parent.browser.scrollID != id {
        Task { @MainActor in self.parent.browser.scrollID = id }
      }
    }

    private func select(_ id: String?) {
      parent.browser.selection = id
      parent.browser.orthographySelection = nil
    }
  }
}

final class LanguageHeaderCell: NSTableHeaderCell {
  var available = true
  var ordered = false
  var ascending = false

  override func draw(withFrame frame: NSRect, in controlView: NSView) {
    NSColor(WorkbenchStyle.paper).setFill()
    frame.fill()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment =
      stringValue == "Speakers" ? .right : stringValue == "Language" ? .left : .center
    let text = stringValue + (ordered ? ascending ? " ↑" : " ↓" : "")
    (text as NSString).draw(
      in: frame.insetBy(dx: stringValue == "Language" ? 24 : 4, dy: 6),
      withAttributes: [
        .font: NSFont.systemFont(
          ofSize: 11, weight: stringValue == "A" || stringValue == "B" ? .bold : .regular),
        .foregroundColor: stringValue == "A" && available
          ? WorkbenchStyle.red
          : stringValue == "B" && available
            ? WorkbenchStyle.blue : NSColor(WorkbenchStyle.secondaryInk),
        .paragraphStyle: paragraph,
      ])
    NSColor(WorkbenchStyle.hairline).setFill()
    let inset: Double = stringValue == "Language" ? 24 : 0
    NSRect(x: frame.minX + inset, y: frame.maxY - 1, width: frame.width - inset, height: 1).fill()
  }
}

final class LanguageSelectionRow: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    NSColor(WorkbenchStyle.ink).setFill()
    NSRect(x: 0, y: 6, width: 2, height: 16).fill()
  }
}

final class LanguageTableCell: NSView {
  var title = ""
  var column = ""
  var current = false
  var mark: LanguageCoverageMark?
  var choose: (() -> Void)?
  override var isFlipped: Bool { true }

  override func accessibilityPerformPress() -> Bool {
    guard let choose else { return false }
    choose()
    return true
  }

  override func draw(_ dirtyRect: NSRect) {
    let ink = NSColor(WorkbenchStyle.ink)
    if let mark {
      let rect = NSRect(x: (bounds.width - 9) / 2, y: 9, width: 9, height: 9)
      ink.setFill()
      NSColor(WorkbenchStyle.secondaryInk).setStroke()
      switch mark {
      case .complete: NSBezierPath(ovalIn: rect).fill()
      case .incomplete:
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 1.5
        path.stroke()
      case .unavailable:
        NSRect(x: rect.minX, y: 13, width: 9, height: 1).fill()
      case .checking:
        let path = NSBezierPath()
        path.appendArc(
          withCenter: NSPoint(x: bounds.midX, y: 13.5), radius: 4.5, startAngle: 45, endAngle: 315)
        path.lineWidth = 1.5
        path.stroke()
      }
    } else if !column.isEmpty {
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineBreakMode = .byTruncatingTail
      paragraph.alignment = column == "Language" ? .left : .right
      (title as NSString).draw(
        in: NSRect(
          x: column == "Language" ? 24 : 4, y: 5,
          width: max(0, bounds.width - (column == "Language" ? 28 : 8)), height: 20),
        withAttributes: [
          .font: NSFont.monospacedDigitSystemFont(
            ofSize: 13, weight: current && column == "Language" ? .semibold : .regular),
          .foregroundColor: ink, .paragraphStyle: paragraph,
        ])
    }
  }
}

final class LanguageTableScrollView: NSScrollView {
  var didScroll: ((NSScrollView) -> Void)?

  override func tile() {
    super.tile()
    guard let table = documentView as? NSTableView else { return }
    let fixed = table.tableColumns.dropFirst().filter { !$0.isHidden }.reduce(0) { $0 + $1.width }
    table.tableColumns[0].width = max(100, contentSize.width - fixed)
    table.frame.size.width = contentSize.width
  }

  override func reflectScrolledClipView(_ clipView: NSClipView) {
    super.reflectScrolledClipView(clipView)
    didScroll?(self)
  }
}
