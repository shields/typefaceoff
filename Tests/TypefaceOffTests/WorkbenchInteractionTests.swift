import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct WorkbenchInteractionTests {
  @Test func matchingPreviewKeepsTheComparisonUnchangedUntilApply() async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let host = WorkbenchTestHost(MatchSheet(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Weight")
    try await host.settle()
    #expect(try await host.element("Apply").isAccessibilityEnabled?() == false)
    try await host.press("x-height")
    try await host.press("Tracking")
    try await host.settle()
    #expect(model.comparison == initial)
    try await host.press("Apply")
    try await host.settle()
    let candidate = try #require(model.comparison.b)
    let aHeight = try #require(FontRenderer.xHeight(config: initial.a, size: initial.a.size))
    let bHeight = try #require(FontRenderer.xHeight(config: candidate, size: candidate.size))
    #expect(abs(aHeight - bHeight) < 0.001)
    #expect(model.comparison.a == initial.a)
    #expect(model.comparison.link?.sizeRatio == candidate.size / initial.a.size)
  }

  @Test(arguments: ["Cancel", "Cancel matching"])
  func cancellingMatchingDiscardsOptions(button: String) async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let host = WorkbenchTestHost(MatchSheet(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("x-height")
    try await host.settle()
    try await host.press(button)
    #expect(model.comparison == initial)
  }

  @Test func matchingWithoutASecondFontIsDisabled() async throws {
    let model = WorkbenchModel(comparison: Comparison(b: nil))
    let host = WorkbenchTestHost(MatchSheet(model: model))
    defer { host.window.close() }
    try await host.settle()
    #expect(try await host.element("Apply").isAccessibilityEnabled?() == false)
    #expect(model.comparison.b == nil)
  }

  @Test func matchingVariableWeightsKeepsTheReferenceUnchanged() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    var comparison = Comparison(a: .init(name), b: .init(name))
    comparison.a.axes[tagNumber("wght")] = 1.2
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(MatchSheet(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Apply")
    #expect(model.comparison.a == comparison.a)
    #expect(model.comparison.b?.weight == comparison.a.weight)
  }

  @Test func inspectorAppearanceAndTypographyActionsRespectUndoAndIsolation() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 246)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Unlock appearance")
    try await host.settle()
    #expect(!model.comparison.appearanceLocked)
    model.edit("Configure sample", undoManager: nil) {
      $0.a.size = 48
      $0.a.tracking = 0.1
      $0.a.features["ot.kern"] = 0
    }
    try await host.settle()
    try await host.press("Reset size")
    try await host.settle()
    #expect(model.comparison.a.size == 22)
    try await host.press("Reset tracking")
    try await host.settle()
    #expect(model.comparison.a.tracking == 0)
    try await host.press("Reset typography")
    try await host.settle()
    #expect(model.comparison.a.features.isEmpty)
    try await host.press("Lock appearance")
    try await host.settle()
    #expect(model.comparison.appearanceLocked)
    model.edit("Resize", undoManager: nil) { $0.a.size = 44 }
    try await host.settle()
    try await host.press("Reset appearance")
    try await host.settle()
    #expect(model.comparison.a.size == 22)
    #expect(model.comparison.b?.size == 22)
  }

  @Test func customTextCanBeCancelledAppliedAndUndone() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Edit text")
    try await host.settle()
    let editor = try #require(
      host.subviews.compactMap { $0 as? NSTextView }.first {
        $0.isEditable && !$0.isFieldEditor && $0.window?.sheetParent === host.window
      })
    host.enter("Discarded sample", in: editor)
    try await host.settle()
    try await host.press("Cancel")
    try await host.settle()
    #expect(model.comparison.sample == .reading)
    #expect(model.comparison.customText.isEmpty)
    try await host.press("Edit text")
    try await host.settle()
    let replacement = try #require(
      host.subviews.compactMap { $0 as? NSTextView }.first {
        $0.isEditable && !$0.isFieldEditor && $0.window?.sheetParent === host.window
      })
    host.enter("A custom specimen with punctuation: @ & !", in: replacement)
    try await host.settle()
    try await host.press("Apply")
    try await host.settle()
    #expect(model.comparison.sample == .custom)
    #expect(model.comparison.text == replacement.string)
    #expect(host.window.sheets.isEmpty)
    try await host.press("Undo")
    try await host.settle()
    #expect(model.comparison.sample == .reading)
  }

  @Test func workbenchSwapAndHighlightControlsKeepIndependentState() async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Swap fonts")
    try await host.settle()
    #expect(model.comparison.a == initial.b)
    #expect(model.comparison.b == initial.a)
    try await host.press("Spacing")
    try await host.settle()
    #expect(model.comparison.spacing && model.comparison.shape)
    try await host.press("Shape")
    try await host.settle()
    #expect(!model.comparison.shape && model.comparison.spacing)
    try await host.press("Spacing")
    try await host.settle()
    #expect(!model.comparison.shape && !model.comparison.spacing)
    try await host.press("Match…")
    try await host.settle()
    #expect(!host.window.sheets.isEmpty)
    try await host.press("Cancel")
    try await host.settle()
    #expect(host.window.sheets.isEmpty)
  }

  @Test(arguments: [Sample.poetry, .alphabet, .numerals])
  func readingSamplesRenderTheirCompleteText(sample: Sample) async throws {
    var comparison = Comparison(b: nil)
    comparison.sample = sample
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel(comparison: comparison)))
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
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(FontInspector(model: model, side: .b), width: 246)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Font B family")
    try await host.settle()
    let initialSearch = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
    host.enter("None", in: initialSearch)
    try await host.settle()
    try await host.press("None")
    try await host.settle()
    #expect(model.comparison.b == nil)
    try await host.press("Font B family")
    try await host.settle()
    let search = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first {
        $0.placeholderString == "Search installed fonts"
      })
    host.enter("Skia", in: search)
    try await host.settle()
    try await host.press("Skia")
    try await host.settle()
    #expect(model.comparison.b?.face.family == "Skia")
    #expect(model.comparison.b?.face.axes.isEmpty == false)
  }

  @Test func glyphButtonsAndCharacterEntrySelectTheRequestedGlyph() async throws {
    var comparison = Comparison(b: nil)
    comparison.mode = .glyph
    comparison.sample = .custom
    comparison.customText = "abc"
    comparison.selectedGlyph = "a"
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Next character")
    try await host.settle()
    #expect(model.comparison.selectedGlyph == "b")
    try await host.press("Previous character")
    try await host.settle()
    #expect(model.comparison.selectedGlyph == "a")
    let field = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Character" })
    host.submit("@", to: field)
    try await host.settle()
    #expect(model.comparison.selectedGlyph == "@")
    host.submit("", to: field)
    try await host.settle()
    #expect(model.comparison.selectedGlyph == "@")
    model.updatePresentation {
      $0.customText = ""
      $0.selectedGlyph = "🦄"
    }
    try await host.settle()
    try await host.press("Next character")
    #expect(model.comparison.selectedGlyph == "\"")
  }

  @Test func sharedSizeSubmissionCalibratesBothFontsAndRejectsInvalidText() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(
      WorkbenchView(model: model).environment(\.locale, Locale(identifier: "de_DE")))
    defer { host.window.close() }
    try await host.settle()
    let field = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first {
        $0.placeholderString == "Size" && $0.convert($0.bounds, to: host.view).minX > 246
          && $0.convert($0.bounds, to: host.view).maxX < 1194
      })
    host.submit("32,5", to: field)
    try await host.settle()
    #expect(model.comparison.a.size == 32.5)
    #expect(model.comparison.b?.size == 32.5)
    #expect(model.comparison.link?.sizeRatio == 1)
    host.submit("invalid", to: field)
    try await host.settle()
    #expect(model.comparison.a.size == 32.5)
    #expect(field.stringValue == "32,5")
    host.setContent(
      WorkbenchView(model: model).environment(\.locale, Locale(identifier: "en_US")))
    try await host.settle()
    #expect(field.stringValue == "32.5")
  }

  @Test(arguments: [480.0, 900.0])
  func inspectorTypographyAndDisclosureControlsChangeOnlyTheirOwnSide(height: Double) async throws {
    let model = WorkbenchModel(comparison: Comparison(a: .init("ArialMT")))
    let originalB = model.comparison.b
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 246, height: height)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Kerning")
    try await host.settle()
    #expect(model.comparison.a.features["ot.kern"] == 0)
    try await host.press("Kerning")
    try await host.settle()
    #expect(model.comparison.a.features["ot.kern"] != 0)
    let scroll = try #require(host.subviews.compactMap { $0 as? NSScrollView }.first)
    let document = try #require(scroll.documentView)
    let expandedHeight = document.frame.height
    try await host.press("Common")
    try await host.settle()
    let collapsedHeight = document.frame.height
    #expect(collapsedHeight < expandedHeight)
    try await host.press("Common")
    try await host.settle()
    #expect(document.frame.height > collapsedHeight)
    try await host.press("Automatic shaping")
    try await host.settle()
    #expect(model.comparison.b == originalB)
  }

  @Test(arguments: [480.0, 900.0])
  func inspectorSlidersAdjustAndResetVariableAxes(height: Double) async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 246, height: height)
    defer { host.window.close() }
    try await host.settle()
    try await host.incrementSlider("Font A Size", title: "Size")
    try await host.settle()
    #expect(model.comparison.a.size > 22)
    #expect(model.comparison.b?.size == model.comparison.a.size)
    let axis = try #require(model.comparison.a.face.axes.first { $0.tag == "wdth" })
    let initial = model.comparison.a.axes[axis.id]
    try await host.incrementSlider("Font A \(axis.name)", title: axis.name)
    try await host.settle()
    #expect(model.comparison.a.axes[axis.id] != initial)
  }

  @Test func workbenchToolbarCanHideAndRestoreBothInspectors() async throws {
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel()))
    defer { host.window.close() }
    try await host.settle()
    for side in ["A", "B"] {
      try await host.press("Toggle font \(side) inspector")
      try await host.settle()
      #expect(!host.elements.contains { $0.accessibilityLabel?() == "Font \(side) family" })
      try await host.press("Toggle font \(side) inspector")
      try await host.settle()
      _ = try await host.element("Font \(side) family")
    }
  }

  @Test func styleAndSamplePickersCommitTheChosenOption() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    let original = model.comparison.a.postScriptName
    let styles = model.catalog.faces(in: model.comparison.a.face.family).map(\.style)
    try await host.choose("Font A style", nativeTitles: styles)
    try await host.settle()
    #expect(model.comparison.a.postScriptName != original)
    let samples = Sample.allCases.map(\.title)
    try await host.choose("Sample", nativeTitles: samples, item: Sample.poetry.title)
    try await host.settle()
    #expect(model.comparison.sample == .poetry)
    for sample in [Sample.alphabet, .numerals] {
      try await host.choose("Sample", nativeTitles: samples, item: sample.title)
      try await host.settle()
      #expect(model.comparison.sample == sample)
    }
    try await host.choose("Sample", nativeTitles: samples, item: Sample.custom.title)
    try await host.settle()
    #expect(!host.window.sheets.isEmpty)
    try await host.press("Cancel")
    try await host.settle()
    #expect(model.comparison.sample == .numerals)
  }

  @Test func rankedCharacterButtonsSwitchToGlyphInspection() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await Task.sleep(for: .seconds(1))
    try await host.settle()
    let button = try #require(
      (host.elements + host.hitElements).first {
        ($0.accessibilityLabel?() ?? "").hasPrefix("Inspect U+")
      })
    let help = try #require(button.accessibilityHelp?())
    #expect(help.contains("\nShape "))
    #expect(help.contains("\nSpacing "))
    #expect(!help.contains(" · ") && !help.contains("#"))
    #expect(button.accessibilityPerformPress?() == true)
    try await host.settle()
    #expect(model.comparison.mode == .glyph)
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
    view = NSHostingView(rootView: AnyView(EmptyView()))
    setContent(content)
    view.sceneBridgingOptions = .all
    window.contentView = view
    if let screen = window.screen {
      window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.maxY))
    }
    window.makeKeyAndOrderFront(nil)
  }

  func setContent(_ content: Content) {
    view.rootView = AnyView(
      content.environment(\.accessibilityEnabled, true)
        .environment(\.workbenchUndoManager, window.undoManager))
  }

  func settle() async throws {
    try await Task.sleep(for: .milliseconds(250))
    view.layoutSubtreeIfNeeded()
  }

  func element(_ label: String) async throws -> AnyObject {
    if let result = visibleElement(label) { return result }
    // Older SwiftUI versions expose only the visible portion of a scroll view.
    for scroll in subviews.compactMap({ $0 as? NSScrollView }) {
      guard let document = scroll.documentView else { continue }
      let original = scroll.contentView.bounds.origin
      let maximum = document.bounds.height - scroll.contentView.bounds.height
      guard maximum > 0 else { continue }
      let step = max(1, scroll.contentView.bounds.height / 2)
      for offset in stride(from: 0, through: maximum + step, by: step) {
        scroll.contentView.scroll(to: NSPoint(x: original.x, y: min(offset, maximum)))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle()
        if let result = visibleElement(label) { return result }
      }
      scroll.contentView.scroll(to: original)
      scroll.reflectScrolledClipView(scroll.contentView)
      try await settle()
    }
    let available = Set(
      (elements + hitElements).flatMap { element in
        [
          element.accessibilityIdentifier?(), element.accessibilityLabel?(),
          element.accessibilityTitle?(),
        ].compactMap { $0 }.filter { !$0.isEmpty }
      }
    ).sorted().joined(separator: ", ")
    throw MissingControl(label: label, available: available)
  }

  private func visibleElement(_ label: String) -> AnyObject? {
    func matches(_ element: AnyObject) -> Bool {
      element.accessibilityIdentifier?() == label || element.accessibilityLabel?() == label
        || element.accessibilityTitle?() == label
    }
    return elements.first(where: matches) ?? hitElements.first(where: matches)
  }

  private struct MissingControl: Error, CustomStringConvertible {
    let label: String
    let available: String
    var description: String { "Missing control: \(label). Available controls: \(available)" }
  }

  func press(_ label: String) async throws {
    if let item = window.toolbar?.items.first(where: { $0.label == label }),
      let action = item.action
    {
      #expect(NSApp.sendAction(action, to: item.target, from: item))
      return
    }
    let control = try await element(label)
    // SwiftUI toolbar proxies can return false after dispatching the action.
    // Callers verify the resulting model or view state after settling.
    _ = control.accessibilityPerformPress?()
  }

  func incrementSlider(_ label: String, title: String) async throws {
    let sliders = subviews.compactMap { $0 as? NSSlider }
    if !sliders.isEmpty {
      // Older SwiftUI omits the native sliders' AX names. The
      // labeled value field immediately above each slider identifies its setting.
      let fields = subviews.compactMap { $0 as? NSTextField }.filter {
        $0.placeholderString == title
      }
      try #require(fields.count == 1, "Expected one value field for \(title)")
      let fieldY = fields[0].convert(fields[0].bounds, to: view).midY
      let slider = try #require(
        sliders.min {
          abs($0.convert($0.bounds, to: view).midY - fieldY)
            < abs($1.convert($1.bounds, to: view).midY - fieldY)
        })
      // AppKit dispatches the action but returns false. Check model changes in
      // the caller rather than using that return value as the success signal.
      _ = slider.accessibilityPerformIncrement()
    } else {
      _ = try await element(label).accessibilityPerformIncrement?()
    }
  }

  func choose(_ label: String, nativeTitles: [String], item: String? = nil) async throws {
    let pickers = subviews.compactMap { $0 as? NSPopUpButton }.filter {
      Set(nativeTitles).isSubset(of: Set($0.itemTitles))
    }
    if !pickers.isEmpty {
      try #require(pickers.count == 1, "Expected one native picker for \(label)")
      let picker = pickers[0]
      let menu = try #require(picker.menu)
      WorkbenchTestMenuSelection.select(
        menu, title: item, selectedIndex: picker.indexOfSelectedItem)
      return
    }
    let control = try await element(label)
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

  func enter(_ value: String, in editor: NSTextView) {
    editor.window?.makeFirstResponder(editor)
    editor.insertText(
      value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
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
      // Small native controls can fall between the fallback grid's sample points.
      for view in descendants(of: root) where view is NSControl {
        let frame = owner.convertToScreen(view.convert(view.bounds, to: nil))
        if let hit = root.accessibilityHitTest(NSPoint(x: frame.midX, y: frame.midY)) {
          result.append(hit as AnyObject)
        }
      }
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

  var subviews: [NSView] { contentRoots.flatMap { descendants(of: $0) } }

  private func descendants(of view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants(of: $0) }
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
    Self.select(menu, title: title)
    menu.cancelTracking()
  }

  static func select(_ menu: NSMenu, title: String?, selectedIndex: Int? = nil) {
    if let title {
      if let index = menu.items.firstIndex(where: { $0.title == title }) {
        menu.performActionForItem(at: index)
      } else {
        Issue.record("Missing menu item: \(title)")
      }
      return
    }
    let selected = selectedIndex ?? menu.items.firstIndex { $0.state == .on } ?? 0
    let next =
      menu.items.indices.dropFirst(selected + 1).first {
        menu.items[$0].isEnabled && !menu.items[$0].isSeparatorItem
      } ?? 0
    menu.performActionForItem(at: next)
  }
}
