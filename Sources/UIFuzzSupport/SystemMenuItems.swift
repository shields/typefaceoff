import Foundation

/// Menu items that open UI outside the app's own windows: Apple's Writing Tools, Share, AutoFill,
/// Dictation, Look Up, Speech, and the text system's Fonts, Colors, Styles, Spelling,
/// Substitutions, and Emoji panels. Some of them prompt for credentials on the host, and a popover
/// or sheet they open can outlive every Escape. Identifiers are AppKit's selector names and
/// identifier constants, which the UI language does not change. Titles are localized and change
/// between releases, so they are what macOS 27 shows in English; an item that neither list names
/// stays offered.
public enum SystemMenuItems {
  public static let identifiers: Set<String> = [
    "startDictation:",
    "orderFrontCharacterPalette:",
    "showWritingTools:",
    "_handleInsertFromContactsCommand:",
    "_handleInsertFromCreditCardsCommand:",
    "_handleInsertFromPasswordsCommand:",
    "_performStandardShareMenuItem:",
    "_rvMenuItemAction",
    "__NSTextViewContextSubmenuIdentifierWritingTools",
    "__NSTextViewContextSubmenuItemIdentifierShowFont",
    "__NSTextViewContextSubmenuItemIdentifierShowColor",
    "_NSMenuItemAutoFillIdentifier",
  ]

  /// Speech, Spelling, Substitutions, and Styles items carry auto-numbered identifiers such as
  /// `_NS:85`, so only their titles identify them.
  public static let titles: Set<String> = [
    "Start Speaking",
    "Stop Speaking",
    "Speech",
    "Show Spelling and Grammar",
    "Show Substitutions",
    "Styles…",
    "Show Fonts",
    "Show Colors",
    "Writing Tools",
    "Show Writing Tools",
    "Summarize",
  ]

  public static func opensSystemUI(identifier: String, title: String) -> Bool {
    identifiers.contains(identifier) || titles.contains(title)
  }
}
