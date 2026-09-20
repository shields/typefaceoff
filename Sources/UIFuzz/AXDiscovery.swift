import ApplicationServices
import Foundation
import UIFuzzSupport

private struct VisibleElement {
  var element: AXUIElement
  var path: [Int]
  var role: String
}

extension AXDriver {
  func availableActions() -> [FuzzAction] {
    var elements = visibleElements()
    // Sheets, popovers, and open menus receive input before the workbench behind them.
    let modal = elements.filter { ["AXSheet", "AXPopover", "AXMenu"].contains($0.role) }
      .max { $0.path.count < $1.path.count }
    if let modal { elements = elements.filter { $0.path.starts(with: modal.path) } }
    var result = ActionExplorer.keyboardActions(includeShortcuts: modal == nil)
    for node in elements {
      let element = node.element
      let target = [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
        .compactMap { attribute($0, of: element) as? String }.first { !$0.isEmpty }
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
            ? node.role != "AXTextArea" && target != "Search installed fonts" : nil)
      }
    }
    return result
  }

  private func visibleElements() -> [VisibleElement] {
    var pending: [(AXUIElement, [Int], CGRect?)] = [(application, [], nil)]
    var visited = Set<CFHashCode>()
    var result: [VisibleElement] = []
    let focusedWindow = attribute(kAXFocusedWindowAttribute, of: application)
    while let (element, path, parentClip) = pending.popLast(), visited.count < 10_000 {
      guard visited.insert(CFHash(element)).inserted,
        attribute("AXHidden", of: element) as? Bool != true
      else { continue }
      let role = attribute(kAXRoleAttribute, of: element) as? String ?? ""
      let subrole = attribute(kAXSubroleAttribute, of: element) as? String ?? ""
      // Keep the campaign in the workbench; window chrome and process-management menus
      // would close or hide the app rather than exercise its controls.
      if ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"].contains(
        subrole)
      {
        continue
      }
      if role == "AXMenuBarItem",
        !["Edit", "View", "Comparison"].contains(
          attribute(kAXTitleAttribute, of: element) as? String ?? "")
      {
        continue
      }
      if role == "AXWindow", subrole == "AXStandardWindow", let focusedWindow,
        !CFEqual(element, focusedWindow)
      {
        continue
      }
      let frame = frame(of: element)
      var clip = parentClip
      if ["AXWindow", "AXSheet", "AXPopover", "AXMenu", "AXScrollArea"].contains(role) {
        guard let frame, !frame.isEmpty else { continue }
        // Menus and popovers may extend outside their parent window.
        clip =
          ["AXMenu", "AXPopover"].contains(role) ? frame : parentClip?.intersection(frame) ?? frame
      }
      if let frame, !frame.isEmpty,
        attribute(kAXEnabledAttribute, of: element) as? Bool != false,
        clip?.contains(CGPoint(x: frame.midX, y: frame.midY)) ?? true
      {
        result.append(VisibleElement(element: element, path: path, role: role))
      }
      for (index, child) in children(of: element).enumerated().reversed() {
        pending.append((child, path + [index], clip))
      }
    }
    return result
  }

  private func frame(of element: AXUIElement) -> CGRect? {
    guard let position = attribute(kAXPositionAttribute, of: element),
      let size = attribute(kAXSizeAttribute, of: element),
      CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
      AXValueGetValue(size as! AXValue, .cgSize, &extent)
    else { return nil }
    return CGRect(origin: origin, size: extent)
  }
}
