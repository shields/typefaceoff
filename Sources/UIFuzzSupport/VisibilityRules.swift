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

import CoreGraphics
import Foundation

public enum PruneReason: String, Codable, Sendable {
  case hidden
  case windowChrome
  case menuBarItem
  case systemUI
  case emptyFrame
}

public enum Disposition: Equatable, Sendable {
  case prune(PruneReason)
  case keep(emits: Bool, clip: CGRect?)
}

public enum VisibilityRules {
  private static let chromeSubroles: Set<String> = [
    "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton",
  ]
  private static let allowedMenus: Set<String> = ["Edit", "View", "Comparison"]
  private static let framedRoles: Set<String> = [
    "AXWindow", "AXSheet", "AXPopover", "AXMenu", "AXScrollArea",
  ]
  /// They are windows of their own, so nothing above them in the tree clips what they hold, even
  /// when the tree nests a context menu inside the scroll area that opened it.
  public static let unclippedRoles: Set<String> = ["AXMenu", "AXPopover"]

  public static func disposition(_ input: VisibilityInput, parentClip: CGRect?) -> Disposition {
    if input.isHidden == true { return .prune(.hidden) }
    // Window chrome and process-management menus would close or hide the app rather than
    // exercise its controls.
    if chromeSubroles.contains(input.subrole) { return .prune(.windowChrome) }
    if input.role == "AXMenuBarItem", !allowedMenus.contains(input.title) {
      return .prune(.menuBarItem)
    }
    if input.role == "AXMenuItem",
      SystemMenuItems.opensSystemUI(identifier: input.identifier, title: input.title)
    {
      return .prune(.systemUI)
    }
    let frame = input.frame
    var clip = parentClip
    if framedRoles.contains(input.role) {
      guard let frame, !frame.isEmpty else { return .prune(.emptyFrame) }
      // Menus and popovers may extend outside their parent window.
      clip = unclippedRoles.contains(input.role) ? frame : parentClip?.intersection(frame) ?? frame
    }
    let emits =
      if let frame, !frame.isEmpty, input.isEnabled != false,
        clip?.contains(CGPoint(x: frame.midX, y: frame.midY)) ?? true
      {
        true
      } else {
        false
      }
    return .keep(emits: emits, clip: clip)
  }
}
