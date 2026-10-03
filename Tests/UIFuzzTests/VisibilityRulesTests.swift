import CoreGraphics
import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct VisibilityRulesTests {
  static let frame = CGRect(x: 10, y: 10, width: 100, height: 30)
  static let clip = CGRect(x: 0, y: 0, width: 500, height: 500)

  func disposition(
    role: String = "AXButton", subrole: String = "", identifier: String = "", title: String = "",
    frame: CGRect? = VisibilityRulesTests.frame, enabled: Bool? = nil, hidden: Bool? = nil,
    clip: CGRect? = nil
  ) -> Disposition {
    VisibilityRules.disposition(
      VisibilityInput(
        role: role, subrole: subrole, identifier: identifier, title: title, frame: frame,
        isEnabled: enabled, isHidden: hidden), parentClip: clip)
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

  static let systemIdentifiers = [
    "startDictation:", "orderFrontCharacterPalette:", "showWritingTools:",
    "_handleInsertFromContactsCommand:", "_handleInsertFromCreditCardsCommand:",
    "_handleInsertFromPasswordsCommand:", "_processRequest:",
    "_performStandardShareMenuItem:", "_rvMenuItemAction", "_searchWithGoogleFromMenu:",
    "__NSTextViewContextSubmenuIdentifierWritingTools",
    "__NSTextViewContextSubmenuItemIdentifierShowFont",
    "__NSTextViewContextSubmenuItemIdentifierShowColor", "_NSMenuItemAutoFillIdentifier",
  ]

  static let systemTitles = [
    "Start Speaking", "Stop Speaking", "Speech", "Services", "Show Spelling and Grammar",
    "Show Substitutions", "Styles…", "Show Fonts", "Show Colors", "Writing Tools",
    "Show Writing Tools", "Summarize",
  ]

  @Test func menuItemsThatOpenSystemUIArePrunedByIdentifier() {
    for identifier in Self.systemIdentifiers {
      #expect(
        disposition(role: "AXMenuItem", identifier: identifier, title: "Something else")
          == .prune(.systemUI), "\(identifier)")
    }
  }

  @Test func menuItemsThatOpenSystemUIArePrunedByTitle() {
    for title in Self.systemTitles {
      #expect(
        disposition(role: "AXMenuItem", identifier: "_NS:85", title: title) == .prune(.systemUI),
        "\(title)")
      #expect(
        disposition(role: "AXMenuItem", title: title) == .prune(.systemUI), "\(title) unnamed")
    }
  }

  @Test func theSystemUIListsHoldExactlyTheNamesThatAreTested() {
    #expect(SystemMenuItems.identifiers == Set(Self.systemIdentifiers))
    #expect(SystemMenuItems.titles == Set(Self.systemTitles))
  }

  @Test func menuItemsThatStayInsideTheAppAreKept() {
    let kept = [
      ("_NS:7", "Cut"), ("_NS:23", "Copy"), ("_NS:29", "Paste"),
      ("_NS:270", "Paste and Match Style"), ("_NS:315", "Font"), ("_NS:50", "Bold"),
      ("_NS:56", "Italic"), ("_NS:61", "Underline"),
      ("__NSTextViewContextSubmenuIdentifierSpellingAndGrammar", "Spelling and Grammar"),
      ("_NS:73", "Check Document Now"), ("_NS:67", "Check Spelling While Typing"),
      ("_NS:154", "Correct Spelling Automatically"),
      ("__NSTextViewContextSubmenuIdentifierSubstitutions", "Substitutions"),
      ("_NS:142", "Smart Quotes"), ("_NS:160", "Smart Dashes"), ("_NS:166", "Text Replacement"),
      ("", "Transformations"), ("undo:", "Undo"), ("cut:", "Cut"), ("selectAll:", "Select All"),
      ("", "Swap fonts"), ("", "Match fonts…"), ("", "Edit sample text…"), ("", ""),
      ("_NSMenuItemLegacyWritingToolsSeparatorIdentifier", ""),
    ]
    for (identifier, title) in kept {
      #expect(
        disposition(role: "AXMenuItem", identifier: identifier, title: title)
          == .keep(emits: true, clip: nil), "\(identifier) \(title)")
    }
  }

  @Test func onlyMenuItemsAreMatchedAgainstTheSystemUINames() {
    for role in ["AXButton", "AXGroup", "AXTextField", "AXMenu"] {
      #expect(
        disposition(role: role, identifier: "showWritingTools:", title: "Summarize")
          == .keep(emits: true, clip: role == "AXMenu" ? Self.frame : nil), "\(role)")
    }
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
