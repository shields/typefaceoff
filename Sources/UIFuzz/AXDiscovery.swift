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

import ApplicationServices
import Foundation
import UIFuzzSupport

struct DiscoveryStats {
  var elements: Int
  /// Standard windows only: the menu bar and overlays are top-level children too.
  var windows: Int
  var scope: WindowScopeSource
  var readErrors: Int
  var focusedRole: String?
  var focusedSubrole: String?
  var focusLocation: FocusLocation?
  var modalRole: String?
  var modalDepth: Int?
  var unlocated: Bool
  var context: String?
}

extension AXDriver {
  /// A focused overlay that discovery cannot locate counts as open: the app still drops a quit.
  func openOverlay() -> QuitPreparation.Overlay? {
    let application = AXNode(self.application, reads: AXReads())
    let capture = Discovery.capture(
      application: application, focusedWindow: { application.focusedWindow() })
    return QuitPreparation.Overlay(capture.modal)
  }

  func availableActions(observe: (DiscoveryStats) -> Void) -> [FuzzAction] {
    let reads = AXReads()
    let application = AXNode(self.application, reads: reads)
    var focused: AXIdentity?
    let capture = Discovery.capture(
      application: application,
      focusedWindow: {
        focused = application.focusedWindow()
        return focused
      })
    let focusedNode = focused.map { AXNode($0.element, reads: reads) }
    var result = ActionExplorer.keyboardActions(
      includeShortcuts: capture.offersShortcuts, inMenu: capture.menuIsOpen)
    let context = FuzzAction.Context.identify(
      rootRole: capture.modal.rootRole, targets: capture.elements.map { $0.node.discoveryTarget })
    for node in capture.elements {
      let element = node.node.element
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
              && ![
                "Search installed fonts", "Search Unicode characters", "Find Character",
                "Search Languages",
              ].contains(target)
            : nil,
          context: context?.forTarget(target))
      }
    }
    observe(
      DiscoveryStats(
        elements: capture.elements.count, windows: capture.scope.standardWindowCount,
        scope: capture.scope.source, readErrors: reads.errors, focusedRole: focusedNode?.role,
        focusedSubrole: focusedNode?.subrole, focusLocation: capture.modal.focus,
        modalRole: capture.modal.rootRole, modalDepth: capture.modal.root?.count,
        unlocated: capture.unlocated,
        context: FuzzAction.Context.logName(rootRole: capture.modal.rootRole, identified: context)))
    return result
  }
}
