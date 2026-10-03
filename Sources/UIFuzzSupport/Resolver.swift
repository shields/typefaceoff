import CoreGraphics
import Foundation

public struct ResolutionRequest: Equatable, Sendable {
  public var target: String?
  public var path: [Int]?
  public var role: String?
  /// Whether the single visible one of several same-named controls may be chosen. Only a live
  /// pick was chosen from what discovery offered, so only a live pick may.
  public var allowVisibleTieBreak: Bool
  /// Whether name searches skip the menu bar, whose menus are slow to read.
  public var excludesMenuBar = false
  var legacyMatchOption: String?

  public init(_ action: FuzzAction, allowVisibleTieBreak: Bool) {
    target = action.target
    path = action.targetPath
    role = action.targetRole
    self.allowVisibleTieBreak = allowVisibleTieBreak
    if let target = action.target, action.kind == .press || action.kind == .click,
      action.sheet != .editor, action.targetRole == nil || action.targetRole == "AXCheckBox",
      action.sheet == .match || ["Tracking", "Size", "Weight"].contains(target)
    {
      legacyMatchOption = "Optimize \(target)"
    }
  }

  public init(target: String, excludesMenuBar: Bool = false) {
    self.target = target
    path = nil
    role = nil
    allowVisibleTieBreak = false
    self.excludesMenuBar = excludesMenuBar
  }

  public var label: String { target ?? path.map { "\($0)" } ?? "<missing target>" }

  /// The campaign-wide identity of a control; unnamed controls share their role's key.
  public var key: String { "\(role ?? "") \(target ?? "<unnamed>")" }

  /// The identity of a control within one run, where an unnamed control's path is stable.
  public var runKey: String {
    guard target == nil, let path else { return key }
    return "\(role ?? "") \(path)"
  }
}

public enum ResolutionStep: String, Codable, Sendable, CaseIterable {
  case path
  case uniqueName
  case visibleName
  case firstName
}

public enum Resolution<Node: AccessibilityNode> {
  case found(Node, ResolutionStep)
  case ambiguous(matches: Int, offered: Int)
  case missing(ResolutionMiss)

  public var node: Node? {
    guard case .found(let node, _) = self else { return nil }
    return node
  }

  public var step: ResolutionStep? {
    guard case .found(_, let step) = self else { return nil }
    return step
  }

  public func failure(for request: ResolutionRequest) -> ResolutionFailure? {
    switch self {
    case .found: nil
    case .ambiguous(let matches, let offered):
      ResolutionFailure(
        kind: .ambiguous(matches: matches, offered: offered), label: request.label)
    case .missing(let miss): ResolutionFailure(kind: .missing(miss), label: request.label)
    }
  }
}

/// Resolves one request against one capture of the tree. Build a fresh resolver per attempt:
/// reads are memoized for the resolver's lifetime and the scope is computed only when needed.
public final class AccessibilityResolver<Node: AccessibilityNode> {
  private let application: Node
  private let focusedWindow: () -> Node.Identity?
  private let nodeLimit: Int
  private let clock: any ResolutionClock
  private let budgetSeconds: TimeInterval
  private var startedAt: TimeInterval = 0
  private var expired = false
  private var skipsMenuBar = false

  private lazy var roots: [Node] = application.children
  private lazy var focused: Node.Identity? = focusedWindow()
  private lazy var topLevel: [TopLevelChild<Node.Identity>] = roots.map {
    TopLevelChild(identity: $0.identity, role: $0.role, subrole: $0.subrole)
  }
  public private(set) lazy var scope = WindowScope(children: topLevel, focused: focused)
  private lazy var scopedRoots: [Node] = roots.indices.filter {
    scope.includes(index: $0, child: topLevel[$0])
  }.map { roots[$0] }

  /// `focusedWindow` is read at most once and only when a standard window's membership depends on
  /// it. A capture that runs past `budgetSeconds` on `clock` resolves to `.missing(.unreadable)`.
  public init(
    application: Node, focusedWindow: @escaping () -> Node.Identity?, nodeLimit: Int = 10_000,
    clock: any ResolutionClock, budgetSeconds: TimeInterval
  ) {
    self.application = application
    self.focusedWindow = focusedWindow
    self.nodeLimit = nodeLimit
    self.clock = clock
    self.budgetSeconds = budgetSeconds
  }

  public func resolve(_ request: ResolutionRequest) -> Resolution<Node> {
    startedAt = clock.now
    expired = false
    skipsMenuBar = request.excludesMenuBar
    let result = search(request)
    if case .found = result { return result }
    return expired || application.readErrors > 0 ? .missing(.unreadable) : result
  }

  private func search(_ request: ResolutionRequest) -> Resolution<Node> {
    if let target = request.legacyMatchOption {
      var replacement = request
      replacement.target = target
      replacement.role = "AXButton"
      if let result = namedInScope(replacement, target: target) { return result }
    }
    guard let path = request.path else { return firstNamed(request.target) }
    var miss = ResolutionMiss.noMatch
    if let first = path.first, roots.indices.contains(first) {
      if pathRootIncluded(first) {
        if let node = descend(path), node.role == request.role,
          request.target.map({ node.hasName($0) }) ?? true
        {
          return .found(node, .path)
        }
      } else {
        miss = .pathOutsideScope
      }
    }
    guard let target = request.target else { return .missing(miss) }
    return namedInScope(request, target: target) ?? .missing(miss)
  }

  private func pathRootIncluded(_ index: Int) -> Bool {
    let node = roots[index]
    guard WindowScope<Node.Identity>.isStandardWindow(role: node.role, subrole: node.subrole)
    else { return true }
    if focused == node.identity { return true }
    return scope.includes(index: index, child: topLevel[index])
  }

  private func descend(_ path: [Int]) -> Node? {
    var node = roots[path[0]]
    for index in path.dropFirst() {
      guard !isOverBudget else { return nil }
      let children = node.children
      guard children.indices.contains(index) else { return nil }
      node = children[index]
    }
    return node
  }

  /// SwiftUI can insert siblings during layout, which makes a recorded path stale while the
  /// control's name and role still identify it.
  private func namedInScope(_ request: ResolutionRequest, target: String) -> Resolution<Node>? {
    var visited: [Node] = []
    var parents: [Int?] = []
    var candidates: [Int] = []
    walk { node, parent in
      visited.append(node)
      parents.append(parent)
      if node.role == request.role, node.hasName(target) { candidates.append(visited.count - 1) }
      return false
    }
    // A walk cut short by the budget cannot show that a name is unique.
    guard !expired else { return nil }
    guard candidates.count > 1 else {
      return candidates.first.map { .found(visited[$0], .uniqueName) }
    }
    let offered = candidates.filter { isOffered($0, visited: visited, parents: parents) }
    if request.allowVisibleTieBreak, offered.count == 1 {
      return .found(visited[offered[0]], .visibleName)
    }
    return .ambiguous(matches: candidates.count, offered: offered.count)
  }

  /// Discovery's visibility rules along the ancestor chain; modal scope is not applied.
  private func isOffered(_ slot: Int, visited: [Node], parents: [Int?]) -> Bool {
    var ancestors: [Int] = []
    var cursor = parents[slot]
    while let parent = cursor {
      ancestors.append(parent)
      cursor = parents[parent]
    }
    var clip: CGRect?
    for index in ancestors.reversed() {
      let input = visited[index].visibilityInput
      guard case .keep(_, let next) = VisibilityRules.disposition(input, parentClip: clip) else {
        return false
      }
      clip = next
    }
    guard
      case .keep(let emits, _) = VisibilityRules.disposition(
        visited[slot].visibilityInput, parentClip: clip)
    else { return false }
    return emits
  }

  /// Stops at the first match, because enumerating every system menu can itself stall AppKit.
  private func firstNamed(_ target: String?) -> Resolution<Node> {
    guard let target else { return .missing(.noTarget) }
    var found: Node?
    walk { node, _ in
      guard node.hasName(target) else { return false }
      found = node
      return true
    }
    return found.map { .found($0, .firstName) } ?? .missing(.noMatch)
  }

  /// Pre-order over the scoped roots in `AXChildren` order; `visit` receives the node and the
  /// visit ordinal of its parent, and returns true to stop.
  private func walk(_ visit: (Node, Int?) -> Bool) {
    let starts = skipsMenuBar ? scopedRoots.filter { $0.role != "AXMenuBar" } : scopedRoots
    var pending = starts.reversed().map { (node: $0, parent: Int?.none) }
    var seen = Set<Node.Identity>()
    var ordinal = 0
    while let (node, parent) = pending.popLast(), ordinal < nodeLimit {
      guard !isOverBudget else { return }
      guard seen.insert(node.identity).inserted else { continue }
      ordinal += 1
      if visit(node, parent) { return }
      pending.append(contentsOf: node.children.reversed().map { (node: $0, parent: ordinal - 1) })
    }
  }

  private var isOverBudget: Bool {
    if clock.now - startedAt >= budgetSeconds { expired = true }
    return expired
  }
}
