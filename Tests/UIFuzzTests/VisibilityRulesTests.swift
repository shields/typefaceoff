import CoreGraphics
import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct VisibilityRulesTests {
  static let frame = CGRect(x: 10, y: 10, width: 100, height: 30)
  static let clip = CGRect(x: 0, y: 0, width: 500, height: 500)

  func disposition(
    role: String = "AXButton", subrole: String = "", title: String = "",
    frame: CGRect? = VisibilityRulesTests.frame, enabled: Bool? = nil, hidden: Bool? = nil,
    clip: CGRect? = nil
  ) -> Disposition {
    VisibilityRules.disposition(
      VisibilityInput(
        role: role, subrole: subrole, title: title, frame: frame, isEnabled: enabled,
        isHidden: hidden), parentClip: clip)
  }

  @Test func hiddenNodesArePruned() {
    #expect(disposition(hidden: true) == .prune(.hidden))
    #expect(disposition(hidden: false) == .keep(emits: true, clip: nil))
    #expect(disposition(role: "AXScrollArea", frame: nil, hidden: true) == .prune(.hidden))
  }

  @Test func windowChromeIsPruned() {
    for subrole in ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"] {
      #expect(disposition(subrole: subrole) == .prune(.windowChrome))
    }
    #expect(disposition(subrole: "AXSearchField") == .keep(emits: true, clip: nil))
  }

  @Test func menuBarItemsOutsideTheAllowlistArePruned() {
    for title in ["Edit", "View", "Comparison"] {
      #expect(
        disposition(role: "AXMenuBarItem", title: title, frame: nil)
          == .keep(emits: false, clip: nil))
    }
    for title in ["Apple", "Typeface/Off", "Window", ""] {
      #expect(disposition(role: "AXMenuBarItem", title: title) == .prune(.menuBarItem))
    }
    #expect(disposition(role: "AXMenuItem", title: "Apple") == .keep(emits: true, clip: nil))
  }

  @Test func framedRolesNeedANonEmptyFrame() {
    for role in ["AXWindow", "AXSheet", "AXPopover", "AXMenu", "AXScrollArea"] {
      #expect(disposition(role: role, frame: nil) == .prune(.emptyFrame))
      #expect(disposition(role: role, frame: .zero) == .prune(.emptyFrame))
      #expect(
        disposition(role: role, frame: CGRect(x: 1, y: 1, width: 0, height: 9))
          == .prune(.emptyFrame))
    }
  }

  @Test func scrollAreasAndWindowsClipToTheirParent() {
    let area = CGRect(x: 100, y: 100, width: 600, height: 600)
    #expect(
      disposition(role: "AXScrollArea", frame: area, clip: Self.clip)
        == .keep(emits: true, clip: area.intersection(Self.clip)))
    #expect(
      disposition(role: "AXScrollArea", frame: area, clip: nil) == .keep(emits: true, clip: area))
    #expect(
      disposition(role: "AXWindow", frame: area, clip: Self.clip)
        == .keep(emits: true, clip: area.intersection(Self.clip)))
    #expect(
      disposition(role: "AXSheet", frame: area, clip: Self.clip)
        == .keep(emits: true, clip: area.intersection(Self.clip)))
  }

  @Test func menusAndPopoversUseTheirOwnFrame() {
    let outside = CGRect(x: 900, y: 900, width: 50, height: 50)
    for role in ["AXMenu", "AXPopover"] {
      #expect(
        disposition(role: role, frame: outside, clip: Self.clip)
          == .keep(emits: true, clip: outside))
    }
  }

  @Test func otherRolesKeepTheParentClip() {
    #expect(
      disposition(role: "AXGroup", clip: Self.clip) == .keep(emits: true, clip: Self.clip))
    #expect(disposition(role: "AXGroup", clip: nil) == .keep(emits: true, clip: nil))
  }

  @Test func emissionNeedsAFrameEnabledAndAMidpointInsideTheClip() {
    #expect(disposition(frame: nil) == .keep(emits: false, clip: nil))
    #expect(disposition(frame: .zero) == .keep(emits: false, clip: nil))
    #expect(disposition(enabled: false) == .keep(emits: false, clip: nil))
    #expect(disposition(enabled: true) == .keep(emits: true, clip: nil))
    let elsewhere = CGRect(x: 600, y: 10, width: 100, height: 30)
    #expect(
      disposition(frame: elsewhere, clip: Self.clip) == .keep(emits: false, clip: Self.clip))
    let straddling = CGRect(x: 420, y: 10, width: 100, height: 30)
    #expect(
      disposition(frame: straddling, clip: Self.clip) == .keep(emits: true, clip: Self.clip))
    #expect(disposition(clip: Self.clip) == .keep(emits: true, clip: Self.clip))
  }

  @Test func disjointScrollAreaEmitsNothingInside() {
    let far = CGRect(x: 900, y: 900, width: 50, height: 50)
    let result = disposition(role: "AXScrollArea", frame: far, clip: Self.clip)
    guard case .keep(let emits, let clip) = result else {
      Issue.record("Expected a kept node")
      return
    }
    #expect(!emits)
    #expect(clip?.isNull == true)
  }
}
