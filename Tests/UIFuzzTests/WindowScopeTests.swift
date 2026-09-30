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
    var description: String { name }
  }

  static var rows: [Row] {
    [
      Row(
        name: "focused window is the second of two",
        children: [standard(1), standard(2), menuBar(3)], focused: 2, source: .focused,
        scopeIndex: 1, standardCount: 2, includes: [false, true, true]),
      Row(
        name: "focused window is the first of two",
        children: [standard(1), standard(2), menuBar(3)], focused: 1, source: .focused,
        scopeIndex: 0, standardCount: 2, includes: [true, false, true]),
      Row(
        name: "no focus selects the front-most standard window",
        children: [floating(1), standard(2), standard(3), menuBar(4)], focused: nil,
        source: .frontmost, scopeIndex: 1, standardCount: 2, includes: [true, true, false, true]),
      Row(
        name: "a focused popover keeps the front-most window in scope",
        children: [standard(1), popover(2), standard(3), menuBar(4)], focused: 2, source: .overlay,
        scopeIndex: 0, standardCount: 2, includes: [true, true, false, true]),
      Row(
        name: "a focused top-level window that is not standard",
        children: [standard(1), floating(2), menuBar(3)], focused: 2, source: .overlay,
        scopeIndex: 0, standardCount: 1, includes: [true, true, true]),
      Row(
        name: "focus on an element that is not a child",
        children: [standard(1), standard(2), menuBar(3)], focused: 99, source: .overlay,
        scopeIndex: 0, standardCount: 2, includes: [true, false, true]),
      Row(
        name: "an overlay with no standard window",
        children: [popover(1), menuBar(2)], focused: 1, source: .overlay, scopeIndex: nil,
        standardCount: 0, includes: [true, true]),
      Row(
        name: "zero windows and no focus",
        children: [menuBar(1), floating(2)], focused: nil, source: .none, scopeIndex: nil,
        standardCount: 0, includes: [true, true]),
      Row(
        name: "no children at all", children: [], focused: nil, source: .none, scopeIndex: nil,
        standardCount: 0, includes: []),
      Row(
        name: "non-standard windows are always included",
        children: [floating(1), standard(2), floating(3)], focused: 2, source: .focused,
        scopeIndex: 1, standardCount: 1, includes: [true, true, true]),
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

  @Test func focusLocationsAreStableStrings() throws {
    #expect(
      [FocusLocation.standardWindow, .applicationChild, .scopeWindow, .otherChild, .notFound]
        .map(\.rawValue)
        == ["standardWindow", "applicationChild", "scopeWindow", "otherChild", "notFound"])
    let encoded = try JSONEncoder().encode([FocusLocation.scopeWindow])
    #expect(try JSONDecoder().decode([FocusLocation].self, from: encoded) == [.scopeWindow])
  }

  struct ModalRow: CustomStringConvertible {
    var name: String
    var elements: [(path: [Int], role: String)]
    var focused: [Int]? = nil
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
      ModalRow(
        name: "a focused overlay is the modal whatever its role",
        elements: [([0], "AXWindow"), ([1], "AXGroup"), ([1, 0], "AXButton")], focused: [1],
        modal: [1], retained: [1, 2]),
      ModalRow(
        name: "a focused overlay that is not offered itself is still the modal",
        elements: [([0], "AXWindow"), ([1, 0], "AXButton"), ([2], "AXMenuBar")], focused: [1],
        modal: [1], retained: [1]),
      ModalRow(
        name: "a focused overlay wins over an equally deep modal that comes first",
        elements: [([0, 1], "AXPopover"), ([0, 2], "AXSheet"), ([0, 2, 0], "AXButton")],
        focused: [0, 2], modal: [0, 2], retained: [1, 2]),
      ModalRow(
        name: "an open menu that is deeper than the focused sheet wins",
        elements: [
          ([0, 1], "AXSheet"), ([0, 1, 0], "AXButton"), ([2, 0, 0], "AXMenu"),
          ([2, 0, 0, 3], "AXMenuItem"),
        ],
        focused: [0, 1], modal: [2, 0, 0], retained: [2, 3]),
      ModalRow(
        name: "depth decides between a focused overlay and a menu",
        elements: [
          ([0, 1, 2], "AXGroup"), ([0, 1, 2, 0], "AXButton"), ([2, 0], "AXMenu"),
          ([2, 0, 1], "AXMenuItem"),
        ],
        focused: [0, 1, 2], modal: [0, 1, 2], retained: [0, 1]),
    ]
  }

  @Test func modalScopeTable() {
    for row in Self.modalRows {
      let paths = row.elements.map(\.path)
      let roles = row.elements.map(\.role)
      let modal = ModalScope.select(paths: paths, roles: roles, focused: row.focused)
      #expect(modal == row.modal, "\(row)")
      let selection = ModalSelection(root: modal)
      #expect(paths.indices.filter { selection.contains(paths[$0]) } == row.retained, "\(row)")
    }
  }

  typealias Candidate = ModalCandidate<Int>

  static func candidate(_ identity: Int, _ path: [Int], _ role: String, offered: Bool = true)
    -> Candidate
  {
    Candidate(identity: identity, path: path, role: role, offered: offered)
  }

  static let modalRoles = ["AXSheet", "AXPopover", "AXMenu"]

  @Test func onlyAnOfferedSheetPopoverOrMenuIsModalByRole() {
    let scope = WindowScope(children: [Self.standard(1)], focused: 1)
    for role in Self.modalRoles {
      let window = Self.candidate(1, [0], "AXWindow")
      let disabled = ModalScope.selection(
        scope: scope, focused: 1,
        traversed: [window, Self.candidate(2, [0, 1], role, offered: false)])
      #expect(disabled.root == nil, "\(role)")
      #expect(disabled.rootRole == nil, "\(role)")
      #expect(!disabled.unlocated, "\(role)")
      #expect(disabled.contains([0, 1, 0]), "\(role)")
      let offered = ModalScope.selection(
        scope: scope, focused: 1, traversed: [window, Self.candidate(2, [0, 1], role)])
      #expect(offered.root == [0, 1], "\(role)")
      #expect(offered.rootRole == role, "\(role)")
      #expect(!offered.contains([0, 0]), "\(role)")
    }
  }

  @Test func aSheetThatIsNotOfferedDoesNotRescueAnUnlocatedFocus() {
    let scope = WindowScope(children: [Self.standard(1), Self.popover(2)], focused: 2)
    for role in Self.modalRoles {
      let selection = ModalScope.selection(
        scope: scope, focused: 3,
        traversed: [
          Self.candidate(1, [0], "AXWindow"), Self.candidate(4, [0, 1], role, offered: false),
        ])
      #expect(selection.unlocated, "\(role)")
      #expect(selection.root == nil, "\(role)")
    }
  }

  @Test func anOverlayThatHasFocusButIsNotFoundIsUnlockedOnlyByAnOfferedModalRole() {
    let scope = WindowScope(children: [Self.standard(1), Self.popover(2)], focused: 9)
    #expect(scope.source == .overlay)
    let window = Self.candidate(1, [0], "AXWindow")
    let none = ModalScope.selection(scope: scope, focused: 9, traversed: [window])
    #expect(none.unlocated)
    #expect(none.focus == .notFound)
    #expect(none.root == nil)
    #expect(!none.contains([0]))
    #expect(!none.contains([1, 0]))
    let byRole = ModalScope.selection(
      scope: scope, focused: 9, traversed: [window, Self.candidate(3, [0, 2], "AXSheet")])
    #expect(!byRole.unlocated)
    #expect(byRole.root == [0, 2])
    #expect(byRole.focus == .notFound)
    let found = ModalScope.selection(
      scope: scope, focused: 3, traversed: [window, Self.candidate(3, [1], "AXGroup")])
    #expect(!found.unlocated)
    #expect(found.root == [1])
    #expect(found.focus == .applicationChild)
  }

  @Test func onlyAnOverlayThatHasFocusCanBeUnlocated() {
    let window = Self.candidate(1, [0], "AXWindow")
    let standard = WindowScope(children: [Self.standard(1)], focused: 1)
    let focusedWindow = ModalScope.selection(scope: standard, focused: 1, traversed: [window])
    #expect(!focusedWindow.unlocated)
    #expect(focusedWindow.focus == .standardWindow)
    let missingWindow = ModalScope.selection(scope: standard, focused: 1, traversed: [])
    #expect(!missingWindow.unlocated)
    #expect(missingWindow.focus == .notFound)
    let unfocused = WindowScope(children: [Self.standard(1)], focused: nil)
    let noFocus = ModalScope.selection(scope: unfocused, focused: nil, traversed: [window])
    #expect(!noFocus.unlocated)
    #expect(noFocus.focus == nil)
    let empty = WindowScope<Int>(children: [], focused: nil)
    #expect(!ModalScope.selection(scope: empty, focused: nil, traversed: []).unlocated)
  }

  @Test func aFocusedOverlayHolderIsLocatedByWhereItSits() {
    let scope = WindowScope(
      children: [Self.standard(1), Self.floating(2), Self.menuBar(3)], focused: 5)
    let traversed = [
      Self.candidate(1, [0], "AXWindow"), Self.candidate(4, [0, 1], "AXSheet"),
      Self.candidate(2, [1], "AXWindow"), Self.candidate(5, [1, 0], "AXSheet"),
    ]
    func location(of identity: Int) -> FocusLocation? {
      ModalScope.selection(scope: scope, focused: identity, traversed: traversed).focus
    }
    #expect(location(of: 4) == .scopeWindow)
    #expect(location(of: 5) == .otherChild)
    #expect(location(of: 2) == .applicationChild)
    #expect(location(of: 99) == .notFound)
  }
}
