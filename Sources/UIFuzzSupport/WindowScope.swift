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
  /// A window that is not a standard child (a popover or sheet) has focus.
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

  /// Resolution and dumps: false only for standard windows other than the scope window. With an
  /// overlay focused the scope is the overlay subtree plus the front-most standard window.
  public func includes(index: Int, child: TopLevelChild<Identity>) -> Bool {
    !Self.isStandardWindow(role: child.role, subrole: child.subrole) || index == scopeIndex
  }

  /// Discovery: an overlay hides every standard window behind it, because a popover or sheet
  /// receives input before the workbench.
  public func discoveryIncludes(index: Int, child: TopLevelChild<Identity>) -> Bool {
    !Self.isStandardWindow(role: child.role, subrole: child.subrole)
      || (source != .overlay && index == scopeIndex)
  }

  public static func isStandardWindow(role: String?, subrole: String?) -> Bool {
    role == "AXWindow" && subrole == "AXStandardWindow"
  }
}

/// Sheets, popovers, and open menus receive input before the workbench behind them.
public enum ModalScope {
  private static let roles: Set<String> = ["AXSheet", "AXPopover", "AXMenu"]

  /// The path of the deepest sheet, popover, or menu (the first when several are equally deep), or
  /// nil when none is open. `paths[i]` is the path of the element with role `roles[i]`.
  public static func select(paths: [[Int]], roles elementRoles: [String]) -> [Int]? {
    paths.indices.filter { roles.contains(elementRoles[$0]) }
      .max { paths[$0].count < paths[$1].count }
      .map { paths[$0] }
  }

  public static func retained(paths: [[Int]], roles elementRoles: [String]) -> (
    modal: [Int]?, indices: [Int]
  ) {
    let modal = select(paths: paths, roles: elementRoles)
    guard let modal else { return (nil, Array(paths.indices)) }
    return (modal, paths.indices.filter { paths[$0].starts(with: modal) })
  }
}
