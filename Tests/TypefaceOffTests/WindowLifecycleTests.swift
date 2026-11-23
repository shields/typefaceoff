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

import AppKit
import Testing

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct WindowLifecycleTests {
  @Test func applicationHasBrandedNameAndIcon() {
    #expect(NSRunningApplication.current.localizedName == "Typeface/Off")
    #expect(NSImage(named: "AppIcon") != nil)
  }

  @Test func aboutShowsVersionAndLinksToBundledAcknowledgments() async throws {
    let url = try #require(Bundle.main.url(forResource: "Acknowledgments", withExtension: "txt"))
    let notice = try String(contentsOf: url, encoding: .utf8)
    #expect(notice.contains("Hyperglot"))
    #expect(notice.contains("Lewis Carroll"))
    let menu = try #require(NSApp.mainMenu?.items.first?.submenu)
    let index = try #require(menu.items.firstIndex { $0.title == "About Typeface/Off" })
    let frontmost = NSWorkspace.shared.frontmostApplication
    menu.performActionForItem(at: index)
    func credits(in window: NSWindow) -> NSTextView? {
      guard let content = window.contentView, window.isVisible else { return nil }
      return descendants(content).compactMap { $0 as? NSTextView }.first {
        $0.string.contains("Acknowledgments")
      }
    }
    try await waitUntil {
      NSApp.windows.contains { credits(in: $0) != nil }
    }
    let window = try #require(NSApp.windows.first { credits(in: $0) != nil })
    defer {
      window.close()
      if let frontmost, frontmost != .current, NSApp.isActive {
        NSApp.yieldActivation(to: frontmost)
        frontmost.activate(from: .current)
      }
      NSApp.deactivate()
    }
    let text = try #require(credits(in: window))
    let version = try #require(
      Bundle.main.object(forInfoDictionaryKey: "TypefaceOffDisplayVersion") as? String)
    #expect(version.wholeMatch(of: /0\.[0-9]{8}\.[0-9]+(-dirty\.[0-9a-f]{7})?/) != nil)
    let content = try #require(window.contentView)
    #expect(
      descendants(content).compactMap { $0 as? NSTextField }.contains {
        $0.stringValue.contains(version)
      })
    let range = (text.string as NSString).range(of: "Acknowledgments")
    let link = try #require(
      text.textStorage?.attribute(.link, at: range.location, effectiveRange: nil) as? URL)
    #expect(link.standardizedFileURL == url.standardizedFileURL)
  }

  @Test(arguments: [NSApplication.ActivationPolicy.prohibited, .regular])
  func applicationLaunchRestoresTheTestHostPolicy(policy: NSApplication.ActivationPolicy) {
    if NSApp.activationPolicy() != policy {
      #expect(NSApp.setActivationPolicy(policy))
    }
    TypefaceOffAppDelegate().applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    #expect(NSApp.activationPolicy() == .prohibited)
  }

  @Test func comparisonsAreIndependentUndoableAndDiscardedOnClose() async throws {
    let launchDeadline = ContinuousClock.now + .seconds(10)
    while !NSApp.windows.contains(where: { $0.title == "Helvetica Neue vs. Arial" }) {
      try #require(
        ContinuousClock.now < launchDeadline,
        "The app did not create its initial comparison window")
      try await Task.sleep(for: .milliseconds(50))
    }
    let initial = try #require(NSApp.windows.first { $0.title == "Helvetica Neue vs. Arial" })
    initial.orderFront(nil)
    try await settle(initial)
    #expect(NSApp.activationPolicy() == .prohibited)
    #expect(!NSApp.isActive)
    #expect(NSApp.windows.contains { $0.isVisible && $0.title == "Helvetica Neue vs. Arial" })
    let fileMenu = try #require(NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu)
    #expect(
      !fileMenu.items.contains { item in
        ["Open", "Save", "Revert", "Duplicate", "Rename", "Move To"].contains {
          item.title.hasPrefix($0)
        }
      })
    #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") == nil)
    #expect(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") == nil)

    let first = try await newWindow(fileMenu)
    defer { first.close() }
    let firstSize = try sizeField(in: first)
    #expect(firstSize.stringValue == "22")
    #expect(!first.isRestorable)
    let undo = try #require(first.undoManager)
    try await submit("44", to: firstSize, in: first)
    try await settle(first) { undo.canUndo }
    first.makeFirstResponder(nil)
    #expect(firstSize.stringValue == "44")
    #expect(undo.canUndo)
    #expect(!first.isDocumentEdited)

    let second = try await newWindow(fileMenu)
    defer { second.close() }
    let secondSize = try sizeField(in: second)
    #expect(secondSize.stringValue == "22")
    #expect(second.undoManager !== undo)
    try editCommand(modifiers: .command, window: first)
    try await settle(first) { firstSize.stringValue == "22" }
    #expect(firstSize.stringValue == "22")
    try editCommand(modifiers: [.command, .shift], window: first)
    try await settle(first) { firstSize.stringValue == "44" }
    #expect(firstSize.stringValue == "44")
    #expect(secondSize.stringValue == "22")

    first.performClose(nil)
    try await settle(first) { !first.isVisible && first.sheets.isEmpty }
    #expect(first.sheets.isEmpty)
    #expect(!first.isVisible)
    let fresh = try await newWindow(fileMenu)
    defer { fresh.close() }
    #expect(try sizeField(in: fresh).stringValue == "22")
    #expect(fresh.undoManager?.canUndo == false)
    try await waitUntil { !NSApp.isActive }
    #expect(!NSApp.isActive)
  }

  private func newWindow(_ menu: NSMenu) async throws -> NSWindow {
    let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
    let index = try #require(
      menu.items.firstIndex {
        $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command
      })
    menu.performActionForItem(at: index)
    let deadline = ContinuousClock.now + .seconds(10)
    while true {
      if let window = NSApp.windows.first(where: {
        $0.isVisible && $0.title == "Helvetica Neue vs. Arial"
          && !existing.contains(ObjectIdentifier($0))
      }) {
        window.contentView?.layoutSubtreeIfNeeded()
        if findSizeField(in: window) != nil { return window }
      }
      try #require(ContinuousClock.now < deadline, "No new comparison window appeared")
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  private func sizeField(in window: NSWindow) throws -> NSTextField {
    try #require(findSizeField(in: window))
  }

  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
  }

  private func findSizeField(in window: NSWindow) -> NSTextField? {
    guard let root = window.contentView else { return nil }
    return descendants(root).compactMap { $0 as? NSTextField }.first {
      $0.accessibilityIdentifier() == "Font A Size field"
    }
  }

  private func editCommand(modifiers: NSEvent.ModifierFlags, window: NSWindow) throws {
    let menu = try #require(NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu)
    let item = try #require(
      menu.items.first {
        $0.keyEquivalent == "z" && $0.keyEquivalentModifierMask == modifiers
      })
    let action = try #require(item.action)
    // Test hosts need not own desktop focus; send the menu action to this window.
    #expect(NSApp.sendAction(action, to: window, from: item))
  }

  private func submit(_ value: String, to field: NSTextField, in window: NSWindow) async throws {
    window.makeFirstResponder(field)
    field.currentEditor()?.string = value
    (field.currentEditor() as? NSTextView)?.didChangeText()
    try await settle(window)
    field.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
  }

  private func settle(_ window: NSWindow) async throws {
    try await Task.sleep(for: .milliseconds(250))
    window.contentView?.layoutSubtreeIfNeeded()
  }

  private func settle(
    _ window: NSWindow, until condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    try await settle(window)
    try await waitUntil(
      condition, step: { try await settle(window) }, sourceLocation: sourceLocation)
  }
}
