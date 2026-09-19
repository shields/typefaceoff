import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct WorkbenchInteractionTests {
  @Test func matchingPreviewKeepsTheDocumentUnchangedUntilApply() async throws {
    let document = WorkbenchDocument()
    let initial = document.comparison
    let host = WorkbenchTestHost(MatchSheet(document: document))
    defer { host.window.close() }
    try await host.settle()
    try host.press("Weight")
    try await host.settle()
    #expect(try host.element("Apply").isAccessibilityEnabled?() == false)
    try host.press("x-height")
    try host.press("Tracking")
    try await host.settle()
    #expect(document.comparison == initial)
    try host.press("Apply")
    try await host.settle()
    let candidate = try #require(document.comparison.b)
    let aHeight = try #require(FontRenderer.xHeight(config: initial.a, size: initial.a.size))
    let bHeight = try #require(FontRenderer.xHeight(config: candidate, size: candidate.size))
    #expect(abs(aHeight - bHeight) < 0.001)
    #expect(document.comparison.a == initial.a)
    #expect(document.comparison.link?.sizeRatio == candidate.size / initial.a.size)
  }

  @Test(arguments: ["Cancel", "Cancel matching"])
  func cancellingMatchingDiscardsOptions(button: String) async throws {
    let document = WorkbenchDocument()
    let initial = document.comparison
    let host = WorkbenchTestHost(MatchSheet(document: document))
    defer { host.window.close() }
    try await host.settle()
    try host.press("x-height")
    try await host.settle()
    try host.press(button)
    #expect(document.comparison == initial)
  }

  @Test func matchingWithoutASecondFontIsDisabled() async throws {
    let document = WorkbenchDocument(comparison: Comparison(b: nil))
    let host = WorkbenchTestHost(MatchSheet(document: document))
    defer { host.window.close() }
    try await host.settle()
    #expect(try host.element("Apply").isAccessibilityEnabled?() == false)
    #expect(document.comparison.b == nil)
  }

  @Test func matchingVariableWeightsKeepsTheReferenceUnchanged() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    var comparison = Comparison(a: .init(name), b: .init(name))
    comparison.a.axes[tagNumber("wght")] = 1.2
    let document = WorkbenchDocument(comparison: comparison)
    let host = WorkbenchTestHost(MatchSheet(document: document))
    defer { host.window.close() }
    try await host.settle()
    try host.press("Apply")
    #expect(document.comparison.a == comparison.a)
    #expect(document.comparison.b?.weight == comparison.a.weight)
  }

  @Test func inspectorAppearanceAndTypographyActionsRespectUndoAndIsolation() async throws {
    let document = WorkbenchDocument()
    let host = WorkbenchTestHost(FontInspector(document: document, side: .a), width: 246)
    defer { host.window.close() }
    try await host.settle()
    // Borderless SwiftUI buttons bridge to NSButton inside the inspector's scroll view.
    let buttons = host.subviews.compactMap { $0 as? NSButton }
    try #require(buttons.count == 5)
    buttons[1].performClick(nil)
    try await host.settle()
    #expect(!document.comparison.appearanceLocked)
    document.edit("Configure sample", undoManager: nil) {
      $0.a.size = 48
      $0.a.tracking = 0.1
      $0.a.features["ot.kern"] = 0
    }
    try await host.settle()
    buttons[2].performClick(nil)
    try await host.settle()
    #expect(document.comparison.a.size == 22)
    buttons[3].performClick(nil)
    try await host.settle()
    #expect(document.comparison.a.tracking == 0)
    buttons[4].performClick(nil)
    try await host.settle()
    #expect(document.comparison.a.features.isEmpty)
    buttons[1].performClick(nil)
    try await host.settle()
    #expect(document.comparison.appearanceLocked)
    document.edit("Resize", undoManager: nil) { $0.a.size = 44 }
    try await host.settle()
    buttons[0].performClick(nil)
    try await host.settle()
    #expect(document.comparison.a.size == 22)
    #expect(document.comparison.b?.size == 22)
  }

  @Test func customTextCanBeCancelledAppliedAndUndone() async throws {
    let document = WorkbenchDocument()
    let host = WorkbenchTestHost(WorkbenchView(document: document))
    defer { host.window.close() }
    try await host.settle()
    try host.press("Edit text")
    try await host.settle()
    let editor = try #require(
      host.subviews.compactMap { $0 as? NSTextView }.first { $0.isEditable })
    editor.string = "Discarded sample"
    editor.didChangeText()
    try host.press("Cancel")
    try await host.settle()
    #expect(document.comparison.sample == .reading)
    #expect(document.comparison.customText.isEmpty)
    try host.press("Edit text")
    try await host.settle()
    let replacement = try #require(
      host.subviews.compactMap { $0 as? NSTextView }.first { $0.isEditable })
    replacement.string = "A custom specimen with punctuation: @ & !"
    replacement.didChangeText()
    try host.press("Apply")
    try await host.settle()
    #expect(document.comparison.sample == .custom)
    #expect(document.comparison.text == replacement.string)
    #expect(host.window.sheets.isEmpty)
    try host.press("Undo")
    try await host.settle()
    #expect(document.comparison.sample == .reading)
  }

  @Test func workbenchSwapAndHighlightControlsKeepIndependentState() async throws {
    let document = WorkbenchDocument()
    let initial = document.comparison
    let host = WorkbenchTestHost(WorkbenchView(document: document))
    defer { host.window.close() }
    try await host.settle()
    try host.press("Swap fonts")
    try await host.settle()
    #expect(document.comparison.a == initial.b)
    #expect(document.comparison.b == initial.a)
    try host.press("Spacing")
    try await host.settle()
    #expect(document.comparison.spacing && document.comparison.shape)
    try host.press("Shape")
    try await host.settle()
    #expect(!document.comparison.shape && document.comparison.spacing)
    try host.press("Spacing")
    try await host.settle()
    #expect(!document.comparison.shape && !document.comparison.spacing)
    try host.press("Match…")
    try await host.settle()
    #expect(!host.window.sheets.isEmpty)
    try host.press("Cancel")
    try await host.settle()
    #expect(host.window.sheets.isEmpty)
  }

  @Test(arguments: [Sample.poetry, .alphabet, .numerals])
  func readingSamplesRenderTheirCompleteText(sample: Sample) async throws {
    var comparison = Comparison(b: nil)
    comparison.sample = sample
    let host = WorkbenchTestHost(WorkbenchView(document: WorkbenchDocument(comparison: comparison)))
    defer { host.window.close() }
    try await host.settle()
    let specimen = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    #expect(specimen.string.contains(sample.text.components(separatedBy: "\n")[0]))
    #expect(specimen.footerRange != nil)
    let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
    #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
  }

  @Test func familyPickerCanRemoveAndRestoreTheSecondFont() async throws {
    let document = WorkbenchDocument()
    let host = WorkbenchTestHost(FontInspector(document: document, side: .b), width: 246)
    defer { host.window.close() }
    try await host.settle()
    try host.press("Font B family")
    try await host.settle()
    try host.press("None")
    try await host.settle()
    #expect(document.comparison.b == nil)
    try host.press("Font B family")
    try await host.settle()
    let search = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first {
        $0.placeholderString == "Search installed fonts"
      })
    host.enter("Skia", in: search)
    try await host.settle()
    try host.press("Skia")
    try await host.settle()
    #expect(document.comparison.b?.face.family == "Skia")
    #expect(document.comparison.b?.face.axes.isEmpty == false)
  }

  @Test func glyphButtonsAndCharacterEntrySelectTheRequestedGlyph() async throws {
    var comparison = Comparison(b: nil)
    comparison.mode = .glyph
    comparison.sample = .custom
    comparison.customText = "abc"
    comparison.selectedGlyph = "a"
    let document = WorkbenchDocument(comparison: comparison)
    let host = WorkbenchTestHost(WorkbenchView(document: document))
    defer { host.window.close() }
    try await host.settle()
    try host.press("Next character")
    try await host.settle()
    #expect(document.comparison.selectedGlyph == "b")
    try host.press("Previous character")
    try await host.settle()
    #expect(document.comparison.selectedGlyph == "a")
    let field = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Character" })
    host.submit("@", to: field)
    try await host.settle()
    #expect(document.comparison.selectedGlyph == "@")
    host.submit("", to: field)
    try await host.settle()
    #expect(document.comparison.selectedGlyph == "@")
    document.updatePresentation {
      $0.customText = ""
      $0.selectedGlyph = "🦄"
    }
    try await host.settle()
    try host.press("Next character")
    #expect(document.comparison.selectedGlyph == "\"")
  }

  @Test func sharedSizeSubmissionCalibratesBothFontsAndRejectsInvalidText() async throws {
    let document = WorkbenchDocument()
    let host = WorkbenchTestHost(
      WorkbenchView(document: document).environment(\.locale, Locale(identifier: "de_DE")))
    defer { host.window.close() }
    try await host.settle()
    let field = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first {
        $0.placeholderString == "Size" && $0.convert($0.bounds, to: host.view).minX > 246
          && $0.convert($0.bounds, to: host.view).maxX < 1194
      })
    host.submit("32,5", to: field)
    try await host.settle()
    #expect(document.comparison.a.size == 32.5)
    #expect(document.comparison.b?.size == 32.5)
    #expect(document.comparison.link?.sizeRatio == 1)
    host.submit("invalid", to: field)
    try await host.settle()
    #expect(document.comparison.a.size == 32.5)
    #expect(field.stringValue == "32,5")
    host.view.rootView = AnyView(
      WorkbenchView(document: document).environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.accessibilityEnabled, true))
    try await host.settle()
    #expect(field.stringValue == "32.5")
  }

  @Test func inspectorTypographyAndDisclosureControlsChangeOnlyTheirOwnSide() async throws {
    let document = WorkbenchDocument(comparison: Comparison(a: .init("ArialMT")))
    let originalB = document.comparison.b
    let host = WorkbenchTestHost(FontInspector(document: document, side: .a), width: 246)
    defer { host.window.close() }
    try await host.settle()
    try host.press("Kerning")
    try await host.settle()
    #expect(document.comparison.a.features["ot.kern"] == 0)
    try host.press("Kerning")
    try await host.settle()
    #expect(document.comparison.a.features["ot.kern"] != 0)
    try host.press("Common")
    try await host.settle()
    try host.press("Common")
    try await host.settle()
    try host.press("Automatic shaping")
    try await host.settle()
    #expect(document.comparison.b == originalB)
  }

  @Test func inspectorSlidersAdjustAndResetVariableAxes() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let document = WorkbenchDocument(comparison: Comparison(a: .init(name), b: .init(name)))
    let host = WorkbenchTestHost(FontInspector(document: document, side: .a), width: 246)
    defer { host.window.close() }
    try await host.settle()
    let size = try host.element("Font A Size")
    #expect(size.accessibilityPerformIncrement?() == true)
    try await host.settle()
    #expect(document.comparison.a.size > 22)
    #expect(document.comparison.b?.size == document.comparison.a.size)
    let axis = try #require(document.comparison.a.face.axes.first { $0.tag == "wdth" })
    let initial = document.comparison.a.axes[axis.id]
    let width = try host.element("Font A \(axis.name)")
    #expect(width.accessibilityPerformIncrement?() == true)
    try await host.settle()
    #expect(document.comparison.a.axes[axis.id] != initial)
  }

  @Test func workbenchToolbarCanHideAndRestoreBothInspectors() async throws {
    let host = WorkbenchTestHost(WorkbenchView(document: WorkbenchDocument()))
    defer { host.window.close() }
    try await host.settle()
    for side in ["A", "B"] {
      try host.press("Toggle font \(side) inspector")
      try await host.settle()
      #expect(!host.elements.contains { $0.accessibilityLabel?() == "Font \(side) family" })
      try host.press("Toggle font \(side) inspector")
      try await host.settle()
      _ = try host.element("Font \(side) family")
    }
  }

  @Test func styleAndSamplePickersCommitTheChosenOption() async throws {
    let document = WorkbenchDocument()
    let host = WorkbenchTestHost(WorkbenchView(document: document))
    defer { host.window.close() }
    try await host.settle()
    let original = document.comparison.a.postScriptName
    try await host.choose("Style")
    try await host.settle()
    #expect(document.comparison.a.postScriptName != original)
    try await host.choose("Sample", item: Sample.poetry.title)
    try await host.settle()
    #expect(document.comparison.sample == .poetry)
    for sample in [Sample.alphabet, .numerals] {
      try await host.choose("Sample", item: sample.title)
      try await host.settle()
      #expect(document.comparison.sample == sample)
    }
    try await host.choose("Sample", item: Sample.custom.title)
    try await host.settle()
    #expect(!host.window.sheets.isEmpty)
    try host.press("Cancel")
    try await host.settle()
    #expect(document.comparison.sample == .numerals)
  }

  @Test func rankedCharacterButtonsSwitchToGlyphInspection() async throws {
    let document = WorkbenchDocument()
    let host = WorkbenchTestHost(WorkbenchView(document: document))
    defer { host.window.close() }
    try await Task.sleep(for: .seconds(1))
    try await host.settle()
    let button = try #require(
      (host.elements + host.hitElements).first {
        ($0.accessibilityLabel?() ?? "").hasPrefix("Inspect U+")
      })
    #expect(button.accessibilityPerformPress?() == true)
    try await host.settle()
    #expect(document.comparison.mode == .glyph)
  }
}

@MainActor final class WorkbenchTestHost<Content: View> {
  let window: WorkbenchTestWindow
  let view: NSHostingView<AnyView>
  private var menuSelection: WorkbenchTestMenuSelection?

  init(_ content: Content, width: Double = 1440, height: Double = 900) {
    NSApp.activate()
    window = WorkbenchTestWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    view = NSHostingView(rootView: AnyView(content.environment(\.accessibilityEnabled, true)))
    view.sceneBridgingOptions = .all
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
  }

  func settle() async throws {
    try await Task.sleep(for: .milliseconds(250))
    view.layoutSubtreeIfNeeded()
  }

  func element(_ label: String) throws -> AnyObject {
    var result = elements.first {
      ($0.accessibilityLabel?() ?? "") == label || ($0.accessibilityTitle?() ?? "") == label
    }
    if result == nil {
      result = hitElements.first {
        ($0.accessibilityLabel?() ?? "") == label || ($0.accessibilityTitle?() ?? "") == label
      }
    }
    if result == nil {
      let description = (elements + hitElements).map {
        "\(type(of: $0)) | \(String(describing: $0.accessibilityLabel?())) | \(String(describing: $0.accessibilityTitle?()))"
      }.joined(separator: "\n")
      try ("Missing: \(label)\n" + description).write(
        to: FileManager.default.temporaryDirectory.appendingPathComponent(
          "typefaceoff-accessibility.txt"), atomically: true, encoding: .utf8)
    }
    return try #require(result, "Missing control: \(label)")
  }

  func press(_ label: String) throws {
    if let item = window.toolbar?.items.first(where: { $0.label == label }),
      let action = item.action
    {
      #expect(NSApp.sendAction(action, to: item.target, from: item))
      return
    }
    let control = try element(label)
    // SwiftUI toolbar proxies can return false after dispatching the action.
    // Callers verify the resulting document or view state after settling.
    _ = control.accessibilityPerformPress?()
  }

  func choose(_ label: String, item: String? = nil) async throws {
    let control = try element(label)
    let selection = WorkbenchTestMenuSelection(title: item)
    menuSelection = selection
    #expect(control.accessibilityPerformPress?() == true)
    for _ in 0..<80 {
      if selection.completed { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    try #require(selection.completed, "Menu selection did not complete: \(label)")
    // AppKit animates dismissal after the selection action and tracking loop end.
    try await Task.sleep(for: .milliseconds(350))
  }

  func enter(_ value: String, in field: NSTextField) {
    field.window?.makeFirstResponder(field)
    field.currentEditor()?.string = value
    (field.currentEditor() as? NSTextView)?.didChangeText()
  }

  func submit(_ value: String, to field: NSTextField) {
    enter(value, in: field)
    field.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
  }

  private var contentRoots: [NSView] {
    [view]
      + (window.sheets + (window.childWindows ?? [])
      + NSApp.windows.filter {
        $0.isVisible && String(describing: type(of: $0)).contains("Popover")
      }).compactMap(\.contentView)
  }

  var hitElements: [AnyObject] {
    var result: [AnyObject] = []
    for root in contentRoots {
      guard let owner = root.window else { continue }
      let bounds = owner.convertToScreen(root.convert(root.bounds, to: nil))
      for y in stride(from: bounds.minY + 8, to: bounds.maxY, by: 16) {
        for x in stride(from: bounds.minX + 8, to: bounds.maxX, by: 16) {
          if let hit = root.accessibilityHitTest(NSPoint(x: x, y: y)) {
            result.append(hit as AnyObject)
          }
        }
      }
    }
    return result
  }

  var subviews: [NSView] {
    func descendants(_ element: NSView) -> [NSView] {
      [element] + element.subviews.flatMap(descendants)
    }
    return contentRoots.flatMap(descendants)
  }

  var elements: [AnyObject] {
    var visited = Set<ObjectIdentifier>()
    func descendants(_ element: AnyObject) -> [AnyObject] {
      guard visited.insert(ObjectIdentifier(element)).inserted else { return [] }
      let children = (element.accessibilityChildren?() ?? []) as [AnyObject]
      let contents = (element.accessibilityContents?() ?? []) as [AnyObject]
      let views = (element as? NSView)?.subviews ?? []
      return [element] + (children + contents + views).flatMap(descendants)
    }
    return ([window] + contentRoots).flatMap { descendants($0) }
  }
}

@MainActor final class WorkbenchTestWindow: NSWindow {
  private let testUndoManager = UndoManager()
  override var undoManager: UndoManager? { testUndoManager }
}

@MainActor private final class WorkbenchTestMenuSelection: NSObject {
  private let title: String?
  private(set) var completed = false

  init(title: String?) {
    self.title = title
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(opened), name: NSMenu.didBeginTrackingNotification, object: nil)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func opened(_ notification: Notification) {
    guard let menu = notification.object as? NSMenu else { return }
    NotificationCenter.default.removeObserver(self)
    let timer = Timer(
      timeInterval: 0.1, target: self, selector: #selector(select), userInfo: menu, repeats: false)
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.add(timer, forMode: .eventTracking)
  }

  @objc private func select(_ timer: Timer) {
    guard let menu = timer.userInfo as? NSMenu else { return }
    defer { completed = true }
    if let title {
      if let index = menu.items.firstIndex(where: { $0.title == title }) {
        menu.performActionForItem(at: index)
      } else {
        Issue.record("Missing menu item: \(title)")
      }
      menu.cancelTracking()
      return
    }
    let selected = menu.items.firstIndex { $0.state == .on } ?? 0
    let next =
      menu.items.indices.dropFirst(selected + 1).first {
        menu.items[$0].isEnabled && !menu.items[$0].isSeparatorItem
      } ?? 0
    menu.performActionForItem(at: next)
    menu.cancelTracking()
  }
}
