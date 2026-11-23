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
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct SpecificationFieldTests {
  @Test func editingPreservesDraftsAndRejectsInvalidEntries() async throws {
    var entries: [(SpecificationValue.Entry, Bool)] = []
    let view = SpecificationFieldView(commit: { _, _ in false })
    func configure(value: Double = 22, precision: Int = 0, enabled: Bool = true) {
      view.configure(
        label: "Font A size", identifier: "Font A Size field", value: value, precision: precision,
        unit: "pt", automatic: false, rules: .init(range: 10...144, step: 1), numberWidth: 40,
        enabled: enabled, locale: Locale(identifier: "en_US")
      ) {
        entries.append(($0, $1))
        return true
      }
    }
    configure()
    #expect(view.field.stringValue == "22")
    #expect(view.field.accessibilityIdentifier() == "Font A Size field")
    let notification = Notification(name: NSControl.textDidChangeNotification, object: view.field)
    view.controlTextDidBeginEditing(notification)
    view.field.stringValue = "21.46"
    view.controlTextDidChange(notification)
    configure(value: 30)
    #expect(view.field.stringValue == "21.46")
    view.submit(both: true)
    #expect(entries.last?.0 == .number(21.46) && entries.last?.1 == true)
    #expect(view.field.stringValue == "21.46")
    configure(value: 21.46, precision: 2)
    view.field.stringValue = "200"
    view.submit(both: false)
    #expect(entries.count == 1 && view.field.stringValue == "21.46")
    view.controlTextDidEndEditing(notification)
    #expect(entries.count == 1)
    view.field.stringValue = "32"
    view.controlTextDidChange(notification)
    view.controlTextDidEndEditing(notification)
    #expect(entries.last?.0 == .number(32))
    configure(enabled: false)
    let count = entries.count
    view.submit(both: false)
    view.increment(1, modifiers: [])
    #expect(entries.count == count && view.stepper.isHidden)
    #expect(SpecificationFieldView(coder: NSCoder()) == nil)
  }

  @Test func modelRejectionRestoresTheAppliedValue() {
    let view = SpecificationFieldView(commit: { _, _ in false })
    view.configure(
      label: "Font A size", identifier: "Font A Size field", value: 22, precision: 0,
      unit: "pt", automatic: false, rules: .init(range: 10...144, step: 1), numberWidth: 40,
      enabled: true, locale: Locale(identifier: "en_US"), commit: { _, _ in false })
    view.field.stringValue = "24"
    view.submit(both: true)
    #expect(view.field.stringValue == "22")
    view.increment(1, modifiers: [])
    #expect(view.field.stringValue == "22")
  }

  @Test func automaticLeadingStepsAndKeyboardCommands() async throws {
    var entries: [SpecificationValue.Entry] = []
    let view = SpecificationFieldView(commit: { _, _ in false })
    view.configure(
      label: "Font B leading", identifier: "Font B Leading field", value: 25.720, precision: 3,
      unit: "pt", automatic: true, rules: .init(range: 1...288, step: 1, allowsAutomatic: true),
      numberWidth: 48, enabled: true, locale: Locale(identifier: "en_US")
    ) { entry, _ in
      entries.append(entry)
      return true
    }
    #expect(view.unitLabel.stringValue == "auto")
    view.field.stringValue = ""
    view.submit(both: false)
    #expect(entries.last == .automatic)
    view.field.stringValue = "invalid"
    view.increment(1, modifiers: [.option])
    #expect(entries.last == .number(25.82))
    view.increment(-1, modifiers: [.shift])
    #expect(entries.last == .number(15.82))
    let editor = NSTextView()
    for selector in [
      #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)),
      #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)),
    ] {
      #expect(view.control(view.field, textView: editor, doCommandBy: selector))
    }
    #expect(
      !view.control(view.field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
    )
    let marked = MarkedSpecificationEditor()
    #expect(
      !view.control(
        view.field, textView: marked, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    view.stepper.doubleValue = 1
    view.stepper.performClick(nil)
    _ = view.stepper.sendAction(view.stepper.action, to: view.stepper.target)
    #expect(view.stepper.doubleValue == 0)
  }

  @Test func hostedFieldsExposeWholeCellFocusAndVisibleSteppers() async throws {
    var entries: [SpecificationValue.Entry] = []
    let host = WorkbenchTestHost(
      SpecificationField(
        label: "Font A size", identifier: "Font A Size field", value: 22, precision: 0,
        unit: "pt", automatic: false, rules: .init(range: 10...144, step: 1), numberWidth: 30
      ) { entry, _ in
        entries.append(entry)
        return true
      }.frame(width: 100, height: 24), width: 200, height: 100
    )
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecificationFieldView }.first)
    view.updateTrackingAreas()
    view.updateTrackingAreas()
    view.resetCursorRects()
    let event = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: host.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 1))
    host.window.makeFirstResponder(nil)
    view.mouseEntered(with: event)
    #expect(view.hovering && !view.stepper.isHidden)
    let hoverImage = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: hoverImage)
    view.mouseExited(with: event)
    let sharedEditor = try #require(host.window.fieldEditor(true, for: nil) as? NSTextView)
    let sharedChecking = sharedEditor.enabledTextCheckingTypes
    view.mouseDown(with: event)
    #expect((view.field.currentEditor() as? NSTextView)?.enabledTextCheckingTypes == 0)
    #expect(view.field.currentEditor() !== sharedEditor)
    try await host.submit("24", to: view.field)
    #expect(entries.last == .number(24))
    let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: image)
    host.window.makeFirstResponder(nil)
    try await host.settle()
    #expect(sharedEditor.enabledTextCheckingTypes == sharedChecking)
    view.field.isEnabled = false
    view.resetCursorRects()
    view.mouseDown(with: event)
    view.cacheDisplay(in: view.bounds, to: image)
  }
}

@MainActor private final class MarkedSpecificationEditor: NSTextView {
  override func hasMarkedText() -> Bool { true }
}
