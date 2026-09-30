import CoreGraphics
import Foundation

public enum PruneReason: String, Codable, Sendable {
  case hidden
  case windowChrome
  case menuBarItem
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
  private static let unclippedRoles: Set<String> = ["AXMenu", "AXPopover"]

  public static func disposition(_ input: VisibilityInput, parentClip: CGRect?) -> Disposition {
    if input.isHidden == true { return .prune(.hidden) }
    // Window chrome and process-management menus would close or hide the app rather than
    // exercise its controls.
    if chromeSubroles.contains(input.subrole) { return .prune(.windowChrome) }
    if input.role == "AXMenuBarItem", !allowedMenus.contains(input.title) {
      return .prune(.menuBarItem)
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
