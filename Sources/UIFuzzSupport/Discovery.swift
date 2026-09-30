import CoreGraphics
import Foundation

public struct DiscoveredElement<Node: AccessibilityNode> {
  public var node: Node
  /// Rooted at the application element, like the paths of recorded actions.
  public var path: [Int]
  public var role: String
}

public struct DiscoveryCapture<Node: AccessibilityNode> {
  public var scope: WindowScope<Node.Identity>
  public var modal: ModalSelection
  /// In traversal order.
  public var elements: [DiscoveredElement<Node>]

  /// Menu shortcuts reach the workbench, so they are offered only when nothing modal is open.
  public var offersShortcuts: Bool { modal.root == nil }
}

public enum Discovery {
  public static let nodeLimit = 10_000

  /// Walks the scope window and every non-standard top-level child. Offers the modal root's
  /// subtree when a modal is open, and every visible control otherwise.
  public static func capture<Node: AccessibilityNode>(
    application: Node, focusedWindow: () -> Node.Identity?, nodeLimit: Int = Discovery.nodeLimit
  ) -> DiscoveryCapture<Node> {
    let roots = application.children
    let children = roots.map {
      TopLevelChild(identity: $0.identity, role: $0.role, subrole: $0.subrole)
    }
    let focused = focusedWindow()
    let scope = WindowScope(children: children, focused: focused)
    var pending = roots.indices.reversed()
      .filter { scope.includes(index: $0, child: children[$0]) }
      .map { (node: roots[$0], path: [$0], clip: CGRect?.none) }
    var visited = Set<Node.Identity>()
    var traversed: [ModalCandidate<Node.Identity>] = []
    var offered: [DiscoveredElement<Node>] = []
    while let (node, path, parentClip) = pending.popLast(), visited.count < nodeLimit {
      guard visited.insert(node.identity).inserted else { continue }
      let input = node.visibilityInput
      guard
        case .keep(let emits, let clip) = VisibilityRules.disposition(input, parentClip: parentClip)
      else { continue }
      traversed.append(
        ModalCandidate(identity: node.identity, path: path, role: input.role, offered: emits))
      if emits { offered.append(DiscoveredElement(node: node, path: path, role: input.role)) }
      for (index, child) in node.children.enumerated().reversed() {
        pending.append((child, path + [index], clip))
      }
    }
    let modal = ModalScope.selection(scope: scope, focused: focused, traversed: traversed)
    return DiscoveryCapture(
      scope: scope, modal: modal, elements: offered.filter { modal.contains($0.path) })
  }
}
