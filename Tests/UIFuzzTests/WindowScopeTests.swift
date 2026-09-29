import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct WindowScopeTests {
  typealias Child = TopLevelChild<Int>

  static func standard(_ identity: Int) -> Child {
    Child(identity: identity, role: "AXWindow", subrole: "AXStandardWindow")
  }
  static func floating(_ identity: Int) -> Child {
    Child(identity: identity, role: "AXWindow", subrole: "AXFloatingWindow")
  }
  static func menuBar(_ identity: Int) -> Child {
    Child(identity: identity, role: "AXMenuBar", subrole: nil)
  }
  static func popover(_ identity: Int) -> Child {
    Child(identity: identity, role: "AXPopover", subrole: nil)
  }

  struct Row: CustomStringConvertible {
    var name: String
    var children: [Child]
    var focused: Int?
    var source: WindowScopeSource
    var scopeIndex: Int?
    var standardCount: Int
    var includes: [Bool]
    var discoveryIncludes: [Bool]
    var description: String { name }
  }

  static var rows: [Row] {
    [
      Row(
        name: "focused window is the second of two",
        children: [standard(1), standard(2), menuBar(3)], focused: 2, source: .focused,
        scopeIndex: 1, standardCount: 2, includes: [false, true, true],
        discoveryIncludes: [false, true, true]),
      Row(
        name: "focused window is the first of two",
        children: [standard(1), standard(2), menuBar(3)], focused: 1, source: .focused,
        scopeIndex: 0, standardCount: 2, includes: [true, false, true],
        discoveryIncludes: [true, false, true]),
      Row(
        name: "no focus selects the front-most standard window",
        children: [floating(1), standard(2), standard(3), menuBar(4)], focused: nil,
        source: .frontmost, scopeIndex: 1, standardCount: 2, includes: [true, true, false, true],
        discoveryIncludes: [true, true, false, true]),
      Row(
        name: "a focused popover hides the workbench from discovery but not from resolution",
        children: [standard(1), popover(2), standard(3), menuBar(4)], focused: 2, source: .overlay,
        scopeIndex: 0, standardCount: 2, includes: [true, true, false, true],
        discoveryIncludes: [false, true, false, true]),
      Row(
        name: "a focused sheet window that is not standard",
        children: [standard(1), floating(2), menuBar(3)], focused: 2, source: .overlay,
        scopeIndex: 0, standardCount: 1, includes: [true, true, true],
        discoveryIncludes: [false, true, true]),
      Row(
        name: "focus on an element that is not a child",
        children: [standard(1), standard(2), menuBar(3)], focused: 99, source: .overlay,
        scopeIndex: 0, standardCount: 2, includes: [true, false, true],
        discoveryIncludes: [false, false, true]),
      Row(
        name: "an overlay with no standard window",
        children: [popover(1), menuBar(2)], focused: 1, source: .overlay, scopeIndex: nil,
        standardCount: 0, includes: [true, true], discoveryIncludes: [true, true]),
      Row(
        name: "zero windows and no focus",
        children: [menuBar(1), floating(2)], focused: nil, source: .none, scopeIndex: nil,
        standardCount: 0, includes: [true, true], discoveryIncludes: [true, true]),
      Row(
        name: "no children at all", children: [], focused: nil, source: .none, scopeIndex: nil,
        standardCount: 0, includes: [], discoveryIncludes: []),
      Row(
        name: "non-standard windows are always included",
        children: [floating(1), standard(2), floating(3)], focused: 2, source: .focused,
        scopeIndex: 1, standardCount: 1, includes: [true, true, true],
        discoveryIncludes: [true, true, true]),
    ]
  }

  @Test func scopeTable() {
    for row in Self.rows {
      let scope = WindowScope(children: row.children, focused: row.focused)
      #expect(scope.source == row.source, "\(row)")
      #expect(scope.scopeIndex == row.scopeIndex, "\(row)")
      #expect(scope.standardWindowCount == row.standardCount, "\(row)")
      #expect(
        row.children.enumerated().map { scope.includes(index: $0, child: $1) } == row.includes,
        "\(row)")
      #expect(
        row.children.enumerated().map { scope.discoveryIncludes(index: $0, child: $1) }
          == row.discoveryIncludes, "\(row)")
    }
  }

  @Test func standardWindowNeedsBothRoleAndSubrole() {
    #expect(WindowScope<Int>.isStandardWindow(role: "AXWindow", subrole: "AXStandardWindow"))
    #expect(!WindowScope<Int>.isStandardWindow(role: "AXWindow", subrole: "AXDialog"))
    #expect(!WindowScope<Int>.isStandardWindow(role: "AXWindow", subrole: nil))
    #expect(!WindowScope<Int>.isStandardWindow(role: nil, subrole: "AXStandardWindow"))
    #expect(!WindowScope<Int>.isStandardWindow(role: "AXSheet", subrole: "AXStandardWindow"))
  }

  @Test func sourcesAreStableStrings() throws {
    #expect(
      [WindowScopeSource.focused, .frontmost, .overlay, .none].map(\.rawValue)
        == ["focused", "frontmost", "overlay", "none"])
    let encoded = try JSONEncoder().encode([WindowScopeSource.overlay])
    #expect(try JSONDecoder().decode([WindowScopeSource].self, from: encoded) == [.overlay])
  }

  struct ModalRow: CustomStringConvertible {
    var name: String
    var elements: [(path: [Int], role: String)]
    var modal: [Int]?
    var retained: [Int]
    var description: String { name }
  }

  static var modalRows: [ModalRow] {
    [
      ModalRow(
        name: "no modal keeps everything",
        elements: [([0], "AXWindow"), ([0, 1], "AXButton"), ([1], "AXMenuBar")], modal: nil,
        retained: [0, 1, 2]),
      ModalRow(
        name: "a sheet keeps only its subtree",
        elements: [
          ([0], "AXWindow"), ([0, 2], "AXSheet"), ([0, 2, 0], "AXButton"), ([1], "AXMenuBar"),
        ],
        modal: [0, 2], retained: [1, 2]),
      ModalRow(
        name: "a popover keeps only its subtree",
        elements: [
          ([0], "AXWindow"), ([0, 3], "AXPopover"), ([0, 3, 1], "AXList"), ([0, 4], "AXButton"),
        ],
        modal: [0, 3], retained: [1, 2]),
      ModalRow(
        name: "an open menu keeps only its subtree",
        elements: [
          ([2, 0], "AXMenuBarItem"), ([2, 0, 0], "AXMenu"), ([2, 0, 0, 1], "AXMenuItem"),
          ([0], "AXWindow"),
        ],
        modal: [2, 0, 0], retained: [1, 2]),
      ModalRow(
        name: "the deepest of nested modals wins",
        elements: [
          ([0, 1], "AXSheet"), ([0, 1, 4], "AXPopover"), ([0, 1, 4, 2], "AXButton"),
          ([0, 1, 5], "AXButton"),
        ],
        modal: [0, 1, 4], retained: [1, 2]),
      ModalRow(
        name: "the first of equally deep modals wins",
        elements: [([0, 1], "AXSheet"), ([0, 2], "AXPopover"), ([0, 1, 0], "AXButton")],
        modal: [0, 1], retained: [0, 2]),
      ModalRow(
        name: "an overlay window without a popover role is not a modal",
        elements: [([1], "AXWindow"), ([1, 0], "AXList"), ([0], "AXWindow")], modal: nil,
        retained: [0, 1, 2]),
      ModalRow(name: "no elements", elements: [], modal: nil, retained: []),
    ]
  }

  @Test func modalScopeTable() {
    for row in Self.modalRows {
      let paths = row.elements.map(\.path)
      let roles = row.elements.map(\.role)
      #expect(ModalScope.select(paths: paths, roles: roles) == row.modal, "\(row)")
      let retained = ModalScope.retained(paths: paths, roles: roles)
      #expect(retained.modal == row.modal, "\(row)")
      #expect(retained.indices == row.retained, "\(row)")
    }
  }
}
