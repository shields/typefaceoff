import Foundation

public struct TopLevelChild<Identity: Hashable> {
  public var identity: Identity
  public var role: String?
  public var subrole: String?

  public init(identity: Identity, role: String?, subrole: String?) {
    self.identity = identity
    self.role = role
    self.subrole = subrole
  }
}

public enum WindowScopeSource: String, Codable, Sendable {
  case focused
  /// No window has focus, so the first standard window in `AXChildren` order (the front-most) is used.
  case frontmost
  /// The focused window is not a standard top-level child: a sheet or popover, which the tree may
  /// nest inside a window or list beside it.
  case overlay
  case none
}

public struct WindowScope<Identity: Hashable> {
  public let source: WindowScopeSource
  /// The `AXChildren` index of the standard window that resolution searches.
  public let scopeIndex: Int?
  public let standardWindowCount: Int

  public init(children: [TopLevelChild<Identity>], focused: Identity?) {
    let standard = children.indices.filter {
      Self.isStandardWindow(role: children[$0].role, subrole: children[$0].subrole)
    }
    standardWindowCount = standard.count
    if let focused {
      if let index = standard.first(where: { children[$0].identity == focused }) {
        source = .focused
        scopeIndex = index
      } else {
        source = .overlay
        scopeIndex = standard.first
      }
    } else {
      source = standard.isEmpty ? .none : .frontmost
      scopeIndex = standard.first
    }
  }

  /// Resolution, discovery, and dumps: false only for standard windows other than the scope
  /// window. With an overlay focused the scope is the front-most standard window plus every
  /// non-standard child; `ModalScope` then narrows what discovery offers.
  public func includes(index: Int, child: TopLevelChild<Identity>) -> Bool {
    !Self.isStandardWindow(role: child.role, subrole: child.subrole) || index == scopeIndex
  }

  public static func isStandardWindow(role: String?, subrole: String?) -> Bool {
    role == "AXWindow" && subrole == "AXStandardWindow"
  }
}

/// Where the window that holds focus sits among the nodes discovery traversed. The driver log
/// records it so a run shows whether the accessibility tree nests a sheet inside its window
/// (`scopeWindow`) or lists it beside the windows (`applicationChild`).
public enum FocusLocation: String, Codable, Sendable {
  case standardWindow
  /// A non-standard overlay listed beside the windows.
  case applicationChild
  case scopeWindow
  /// Inside a non-standard top-level child, such as a floating window.
  case otherChild
  case notFound
}

struct ModalCandidate<Identity: Hashable> {
  var identity: Identity
  var path: [Int]
  var role: String
  var offered: Bool
}

public struct ModalSelection: Equatable, Sendable {
  /// Nil when no window has focus.
  public var focus: FocusLocation?
  /// The path of the overlay whose subtree discovery offers, or nil when nothing is modal.
  public var root: [Int]?
  public var rootRole: String?
  /// An overlay has focus but nothing locates it, so the controls it covers cannot be told from
  /// the ones a user can reach. Nothing is offered.
  public var unlocated = false

  public func contains(_ path: [Int]) -> Bool {
    !unlocated && (root.map { path.starts(with: $0) } ?? true)
  }
}

/// Sheets, popovers, and open menus receive input before the workbench behind them.
public enum ModalScope {
  private static let roles: Set<String> = ["AXSheet", "AXPopover", "AXMenu"]

  /// The path of the deepest sheet, popover, or menu (the first when several are equally deep), or
  /// nil when none is open. `paths[i]` is the path of the element with role `roles[i]`.
  ///
  /// `focused` is the path of an overlay that holds focus. Whatever its role, it is a candidate,
  /// and it wins ties.
  public static func select(
    paths: [[Int]], roles elementRoles: [String], focused: [Int]? = nil
  ) -> [Int]? {
    let deepest = paths.indices.filter { roles.contains(elementRoles[$0]) }
      .max { paths[$0].count < paths[$1].count }
      .map { paths[$0] }
    guard let focused else { return deepest }
    guard let deepest, deepest.count > focused.count else { return focused }
    return deepest
  }

  /// The one rule that discovery and tree dumps share. Only a focused overlay, which is not a
  /// standard top-level child, can be the root by focus: a focused standard window is the scope,
  /// not a modal. The holder is looked up among every traversed node, because an overlay that has
  /// focus is modal even when discovery would not offer the overlay itself. Role-based candidates
  /// come from offered nodes only, so a disabled sheet that holds no focus is not modal.
  static func selection<Identity: Hashable>(
    scope: WindowScope<Identity>, focused: Identity?, traversed: [ModalCandidate<Identity>]
  ) -> ModalSelection {
    let holder = focused.flatMap { identity in traversed.first { $0.identity == identity } }
    let offered = traversed.filter(\.offered)
    let overlay = scope.source == .overlay
    let root = select(
      paths: offered.map(\.path), roles: offered.map(\.role), focused: overlay ? holder?.path : nil)
    return ModalSelection(
      focus: focused == nil ? nil : location(of: holder, in: scope), root: root,
      rootRole: root.flatMap { root in traversed.first { $0.path == root }?.role },
      unlocated: overlay && root == nil)
  }

  private static func location<Identity: Hashable>(
    of holder: ModalCandidate<Identity>?, in scope: WindowScope<Identity>
  ) -> FocusLocation {
    guard let holder else { return .notFound }
    if holder.path.count == 1 {
      return scope.source == .focused ? .standardWindow : .applicationChild
    }
    return holder.path[0] == scope.scopeIndex ? .scopeWindow : .otherChild
  }
}
