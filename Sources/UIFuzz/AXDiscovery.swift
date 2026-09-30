import ApplicationServices
import CoreGraphics
import Foundation
import UIFuzzSupport

private struct VisibleElement {
  var node: AXNode
  var path: [Int]
  var role: String

  var element: AXUIElement { node.element }
}

struct DiscoveryStats {
  var elements: Int
  /// Standard windows only: the menu bar and overlays are top-level children too.
  var windows: Int
  var scope: WindowScopeSource
  var readErrors: Int
}

extension AXDriver {
  func availableActions(observe: (DiscoveryStats) -> Void) -> [FuzzAction] {
    let reads = AXReads()
    let application = AXNode(self.application, reads: reads)
    let topLevel = application.children.map {
      TopLevelChild(identity: $0.identity, role: $0.role, subrole: $0.subrole)
    }
    let scope = WindowScope(children: topLevel, focused: application.focusedWindow())
    let offered = visibleElements(of: application, topLevel: topLevel, scope: scope)
    // Sheets, popovers, and open menus receive input before the workbench behind them.
    let retained = ModalScope.retained(paths: offered.map(\.path), roles: offered.map(\.role))
    let elements = retained.indices.map { offered[$0] }
    var result = ActionExplorer.keyboardActions(includeShortcuts: retained.modal == nil)
    for node in elements {
      let element = node.element
      let target = node.node.discoveryTarget
      var supported: CFArray?
      AXUIElementCopyActionNames(element, &supported)
      let names = supported as? [String] ?? []
      var kinds: [FuzzAction.Kind] = []
      for (name, kind): (String, FuzzAction.Kind) in [
        (kAXPressAction, .press), (kAXIncrementAction, .increment),
        (kAXDecrementAction, .decrement), (kAXShowMenuAction, .showMenu),
      ] where names.contains(name) {
        kinds.append(kind)
      }
      let text = ["AXTextField", "AXTextArea", "AXComboBox"].contains(node.role)
      var settable = DarwinBoolean(false)
      if text,
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
          == .success,
        settable.boolValue
      {
        kinds.append(.setValue)
      }
      if !kinds.isEmpty || ["AXRow", "AXCell", "AXSlider", "AXSplitter"].contains(node.role)
        || target == "Glyph canvas"
      {
        kinds.append(.click)
      }
      if node.role == "AXScrollArea" || target == "Glyph canvas" {
        kinds.append(.scroll)
      }
      if ["AXSlider", "AXSplitter"].contains(node.role) || target == "Glyph canvas" {
        kinds.append(.drag)
      }
      result += kinds.map {
        FuzzAction(
          kind: $0, target: target, targetPath: node.path, targetRole: node.role,
          commitValue: $0 == .setValue
            ? node.role != "AXTextArea"
              && !["Search installed fonts", "Search Unicode characters"].contains(target)
            : nil)
      }
    }
    observe(
      DiscoveryStats(
        elements: elements.count, windows: scope.standardWindowCount, scope: scope.source,
        readErrors: reads.errors))
    return result
  }

  private func visibleElements(
    of application: AXNode, topLevel: [TopLevelChild<AXIdentity>], scope: WindowScope<AXIdentity>
  ) -> [VisibleElement] {
    var pending: [(AXNode, [Int], CGRect?)] = [(application, [], nil)]
    var visited = Set<AXIdentity>()
    var result: [VisibleElement] = []
    while let (node, path, parentClip) = pending.popLast(), visited.count < 10_000 {
      guard visited.insert(node.identity).inserted,
        case .keep(let emits, let clip) = VisibilityRules.disposition(
          node.visibilityInput, parentClip: parentClip)
      else { continue }
      if emits { result.append(VisibleElement(node: node, path: path, role: node.role)) }
      for (index, child) in node.children.enumerated().reversed() {
        if path.isEmpty, !scope.discoveryIncludes(index: index, child: topLevel[index]) {
          continue
        }
        pending.append((child, path + [index], clip))
      }
    }
    return result
  }
}
