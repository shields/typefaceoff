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

import Foundation

/// Menu items that open UI outside the app's own windows: Apple's Writing Tools, Services, Share,
/// AutoFill, Dictation, Look Up, Speech, and the text system's Fonts, Colors, Styles, Spelling,
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
    "_processRequest:",
    "_performStandardShareMenuItem:",
    "_rvMenuItemAction",
    "_searchWithGoogleFromMenu:",
    "__NSTextViewContextSubmenuIdentifierWritingTools",
    "__NSTextViewContextSubmenuItemIdentifierShowFont",
    "__NSTextViewContextSubmenuItemIdentifierShowColor",
    "_NSMenuItemAutoFillIdentifier",
  ]

  /// Services has no identifier. Speech, Spelling, Substitutions, and Styles items carry
  /// auto-numbered identifiers such as `_NS:85`, so only their titles identify them.
  public static let titles: Set<String> = [
    "Start Speaking",
    "Stop Speaking",
    "Speech",
    "Services",
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
