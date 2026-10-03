import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct WorkbenchInteractionTests {
  @Test func missingControlsRespectTheDeadlineAcrossLongScrollViews() async throws {
    let host = WorkbenchTestHost(
      ScrollView {
        VStack {
          Button("Visible deadline test control") {}
          Text("Scrollable content").frame(height: 20_000)
        }
      })
    defer { host.window.close() }
    try await host.settle()
    #expect(try await host.element("Visible deadline test control").accessibilityRole?() == .button)
    try #require(
      host.subviews.compactMap { $0 as? NSScrollView }.contains {
        ($0.documentView?.bounds.height ?? 0) > 10_000
      })
    let start = ContinuousClock.now
    let failure = await #expect(throws: (any Error).self) {
      _ = try await host.element("Missing deadline test control", timeout: .milliseconds(100))
    }
    #expect(String(describing: failure).contains("Missing control: Missing deadline test control"))
    #expect(start.duration(to: .now) < .seconds(5))
  }

  @Test func matchingPreviewKeepsTheComparisonUnchangedUntilApply() async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let fit = FontFitModel(load: SimilarityModelTests.fitResult)
    let host = WorkbenchTestHost(MatchSheet(model: model, fit: fit))
    defer { host.window.close() }
    try await host.settle()
    let expectedSize = (initial.b?.size ?? 0) + 2
    try await host.press("Size")
    try await host.settle(
      until: { fit.result?.proposed.size == expectedSize && host.isEnabled("Apply") },
      describing: "fit result \(String(describing: fit.result))")
    #expect(model.comparison == initial)
    #expect(try await host.element("Apply").isAccessibilityEnabled?() == true)
    try await host.press("Apply")
    try await host.settle(
      until: { model.comparison.b?.size == expectedSize },
      describing: "b size \(String(describing: model.comparison.b?.size))")
    let candidate = try #require(model.comparison.b)
    #expect(candidate.size == (initial.b?.size ?? 0) + 2)
    #expect(model.comparison.a == initial.a)
    #expect(model.comparison.link?.sizeRatio == candidate.size / initial.a.size)
    host.window.undoManager?.undo()
    #expect(model.comparison == initial)
  }

  @Test(arguments: ["Cancel", "Cancel matching"])
  func cancellingMatchingDiscardsOptions(button: String) async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let host = WorkbenchTestHost(MatchSheet(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Size")
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
    let fit = FontFitModel(load: SimilarityModelTests.fitResult)
    let host = WorkbenchTestHost(MatchSheet(model: model, fit: fit))
    defer { host.window.close() }
    try await host.settle(
      until: { fit.result?.improved == true && host.isEnabled("Apply") },
      describing: "fit result \(String(describing: fit.result))")
    try await host.press("Apply")
    #expect(model.comparison.a == comparison.a)
    #expect(model.comparison.b?.postScriptName == comparison.b?.postScriptName)
    #expect(model.comparison.b?.weight != comparison.b?.weight)
  }

  @Test func inspectorAppearanceAndTypographyActionsRespectUndoAndIsolation() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 246)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Unlock appearance")
    try await host.settle { !model.comparison.appearanceLocked }
    #expect(!model.comparison.appearanceLocked)
    model.edit("Configure sample", undoManager: nil) {
      $0.a.size = 48
      $0.a.tracking = 0.1
      $0.a.features["ot.kern"] = 0
    }
    try await host.settle {
      host.subviews.compactMap { $0 as? NSTextField }.contains {
        $0.placeholderString == "Size" && $0.stringValue == "48"
      }
    }
    try await host.press("Reset size")
    try await host.settle { model.comparison.a.size == 22 }
    #expect(model.comparison.a.size == 22)
    try await host.press("Reset tracking")
    try await host.settle { model.comparison.a.tracking == 0 }
    #expect(model.comparison.a.tracking == 0)
    try await host.press("Reset typography")
    try await host.settle { model.comparison.a.features.isEmpty }
    #expect(model.comparison.a.features.isEmpty)
    try await host.press("Lock appearance")
    try await host.settle { model.comparison.appearanceLocked }
    #expect(model.comparison.appearanceLocked)
    model.edit("Resize", undoManager: nil) { $0.a.size = 44 }
    try await host.settle()
    try await host.press("Reset appearance")
    try await host.settle { model.comparison.a.size == 22 && model.comparison.b?.size == 22 }
    #expect(model.comparison.a.size == 22)
    #expect(model.comparison.b?.size == 22)
  }

  @Test func leadingControlsSupportAutoLinkingAndUndo() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 246, height: 900)
    defer { host.window.close() }
    try await host.settle()
    let field = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first {
        $0.placeholderString == "Leading"
      })
    let automatic = SpecimenText.automaticLeading(model.comparison.a)
    #expect(field.stringValue == automatic.formatted(.number.precision(.fractionLength(0...3))))
    #expect(!field.isEnabled)
    try await host.press("Font A Auto leading")
    try await host.settle { model.comparison.a.leading == automatic && field.isEnabled }
    #expect(model.comparison.b?.leading == automatic)
    host.window.undoManager?.undo()
    #expect(model.comparison.a.leading == nil && model.comparison.b?.leading == nil)
    host.window.undoManager?.redo()
    #expect(model.comparison.a.leading == automatic && model.comparison.b?.leading == automatic)
    try await host.settle()
    try await host.submit("32", to: field)
    try await host.settle { model.comparison.a.leading == 32 && model.comparison.b?.leading == 32 }
    host.window.makeFirstResponder(nil)
    host.window.undoManager?.undo()
    #expect(model.comparison.a.leading == automatic && model.comparison.b?.leading == automatic)
    host.window.undoManager?.redo()
    #expect(model.comparison.a.leading == 32 && model.comparison.b?.leading == 32)
    try await host.settle()
    try await host.press("Font A Auto leading")
    try await host.settle {
      model.comparison.a.leading == nil && model.comparison.b?.leading == nil && !field.isEnabled
    }
    let sizeField = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Size" })
    try await host.submit("40", to: sizeField)
    let resized = SpecimenText.automaticLeading(model.comparison.a)
    #expect(resized > automatic)
    #expect(field.stringValue == resized.formatted(.number.precision(.fractionLength(0...3))))
    try await host.press("Font A Auto leading")
    try await host.settle { model.comparison.a.leading == resized }
    try await host.incrementSlider("Font A Leading", title: "Leading")
    try await host.settle { model.comparison.a.leading != resized }
    #expect(model.comparison.a.leading == model.comparison.b?.leading)
    try await host.press("Unlock appearance")
    try await host.settle { !model.comparison.appearanceLocked }
    let b = model.comparison.b
    try await host.press("Reset leading")
    try await host.settle { model.comparison.a.leading == nil }
    #expect(model.comparison.b == b)
    #expect(!field.isEnabled)
    try await host.press("Font A Auto leading")
    try await host.settle { field.isEnabled }
    try await host.submit("38", to: field)
    try await host.settle { model.comparison.a.leading == 38 }
    try await host.press("Reset appearance")
    try await host.settle { model.comparison.a.leading == nil }
    #expect(model.comparison.b == b)
  }

  @Test func customTextCanBeCancelledAppliedAndUndone() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Edit text")
    try await host.settle { sheetEditor(host) != nil }
    let editor = try #require(sheetEditor(host))
    host.enter("Discarded sample", in: editor)
    try await host.settle()
    try await host.press("Cancel")
    try await host.settle { host.window.sheets.isEmpty }
    #expect(model.comparison.sample == .reading)
    #expect(model.comparison.customText.isEmpty)
    try await host.press("Edit text")
    try await host.settle { sheetEditor(host) != nil }
    let replacement = try #require(sheetEditor(host))
    host.enter("A custom specimen with punctuation: @ & !", in: replacement)
    try await host.settle()
    try await host.press("Apply")
    try await host.settle { host.window.sheets.isEmpty }
    #expect(model.comparison.sample == .custom)
    #expect(model.comparison.text == replacement.string)
    try await host.press("Undo")
    try await host.settle { model.comparison.sample == .reading }
    #expect(model.comparison.sample == .reading)
  }

  @Test func workbenchSwapAndHighlightControlsKeepIndependentState() async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Swap fonts")
    try await host.settle { model.comparison.a == initial.b && model.comparison.b == initial.a }
    #expect(model.comparison.a == initial.b)
    #expect(model.comparison.b == initial.a)
    try await host.press("Spacing")
    try await host.settle { model.comparison.spacing && model.comparison.shape }
    #expect(model.comparison.spacing && model.comparison.shape)
    try await host.press("Shape")
    try await host.settle { !model.comparison.shape && model.comparison.spacing }
    #expect(!model.comparison.shape && model.comparison.spacing)
    try await host.press("Spacing")
    try await host.settle { !model.comparison.shape && !model.comparison.spacing }
    #expect(!model.comparison.shape && !model.comparison.spacing)
    #expect(model.comparison.frequency)
    try await host.press("Frequency")
    try await host.settle { !model.comparison.frequency }
    #expect(!model.comparison.frequency)
    try await host.press("Frequency")
    try await host.settle { model.comparison.frequency }
    #expect(model.comparison.frequency)
    try await host.press("Match…")
    try await host.settle { !host.window.sheets.isEmpty }
    #expect(!host.window.sheets.isEmpty)
    try await host.press("Cancel")
    try await host.settle { host.window.sheets.isEmpty }
  }

  @Test(arguments: [Sample.reading, .alphabet, .numerals])
  func readingSamplesRenderTheirCompleteText(sample: Sample) async throws {
    var comparison = Comparison(b: nil)
    comparison.sample = sample
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel(comparison: comparison)))
    defer { host.window.close() }
    try await host.settle {
      host.subviews.compactMap { $0 as? SpecimenNSTextView }.first?.string == sample.text
    }
    let specimen = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    #expect(specimen.string == sample.text)
    let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
    #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
  }

  @Test func familyPickerCanRemoveAndRestoreTheSecondFont() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle { host.window.title == "Helvetica Neue vs. Arial" }
    #expect(host.window.title == "Helvetica Neue vs. Arial")
    try await host.press("Font B family")
    try await host.settle { host.subviews.contains { $0 is NSSearchField } }
    let initialSearch = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
    host.enter("None", in: initialSearch)
    try await host.settle()
    try await host.press("None")
    try await host.settle { model.comparison.b == nil && host.window.title == "Helvetica Neue" }
    #expect(model.comparison.b == nil)
    #expect(host.window.title == "Helvetica Neue")
    try await host.press("Font B family")
    try await host.settle { installedFontsSearch(host) != nil }
    let search = try #require(installedFontsSearch(host))
    host.enter("Skia", in: search)
    try await host.settle()
    try await host.press("Skia")
    try await host.settle {
      model.comparison.b?.face.family == "Skia" && model.comparison.b?.face.axes.isEmpty == false
        && host.window.title == "Helvetica Neue vs. Skia"
    }
    #expect(model.comparison.b?.face.family == "Skia")
    #expect(model.comparison.b?.face.axes.isEmpty == false)
    #expect(host.window.title == "Helvetica Neue vs. Skia")
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
    try await host.settle { model.comparison.selectedGlyph == "b" }
    #expect(model.comparison.selectedGlyph == "b")
    try await host.press("Previous character")
    try await host.settle { model.comparison.selectedGlyph == "a" }
    #expect(model.comparison.selectedGlyph == "a")
    let field = try #require(characterField(host))
    try await host.submit("@", to: field)
    try await host.settle { model.comparison.selectedGlyph == "@" }
    #expect(model.comparison.selectedGlyph == "@")
    try await host.submit("", to: field)
    try await host.settle { model.comparison.selectedGlyph == "@" && field.stringValue == "@" }
    #expect(model.comparison.selectedGlyph == "@")
    #expect(field.stringValue == "@")
    model.updatePresentation {
      $0.customText = ""
      $0.selectedGlyph = "🦄"
    }
    try await host.settle { fieldScalars(host) == ["🦄"] }
    try await host.press("Next character")
    #expect(model.comparison.selectedGlyph == "!")
    model.updatePresentation { $0.selectedGlyph = "🦄" }
    try await host.settle()
    try await host.press("Previous character")
    #expect(model.comparison.selectedGlyph == "~")
  }

  @Test func modeSegmentsSwitchViewsThroughAccessibility() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Glyph")
    try await host.settle { model.comparison.mode == .glyph }
    try await host.press("Text")
    try await host.settle { model.comparison.mode == .text }
  }

  @Test func canonicallyEquivalentCharactersRemainDistinct() async throws {
    var comparison = Comparison(b: nil)
    comparison.mode = .glyph
    comparison.selectedGlyph = ";"
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle { characterField(host) != nil }
    let field = try #require(characterField(host))
    model.updatePresentation { $0.selectedGlyph = "\u{37E}" }
    try await host.settle { glyphCanvasLabel(host)?.hasPrefix("U+037E") == true }
    #expect(model.comparison.selectedScalars == ["\u{37E}"])
    let canvas = try await host.element("Glyph canvas")
    #expect(canvas.accessibilityLabel?()?.hasPrefix("U+037E GREEK QUESTION MARK.") == true)
    field.window?.makeFirstResponder(field)
    let editor = try #require(field.currentEditor())
    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    try await host.settle()
    #expect(model.comparison.selectedScalars == ["\u{37E}"])
    model.updatePresentation {
      $0.sample = .custom
      $0.customText = "\u{E9}"
      $0.selectedGlyph = "e\u{301}"
    }
    try await host.settle { glyphCanvasLabel(host)?.hasPrefix("U+0065") == true }
    try await host.press("Next character")
    #expect(model.comparison.selectedGlyph == "!")
  }

  @Test func sharedSizeSubmissionCalibratesBothFontsAndRejectsInvalidText() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(
      WorkbenchView(model: model).environment(\.locale, Locale(identifier: "de_DE")))
    defer { host.window.close() }
    let sizeField: () -> NSTextField? = {
      host.subviews.compactMap { $0 as? NSTextField }.first {
        $0.placeholderString == "Size" && $0.convert($0.bounds, to: host.view).minX > 246
          && $0.convert($0.bounds, to: host.view).maxX < host.view.bounds.width - 246
      }
    }
    try await host.settle(
      until: { sizeField() != nil }, describing: "no Size field between the inspectors")
    let field = try #require(sizeField())
    try await host.submit("32,5", to: field)
    try await host.settle(
      until: { model.comparison.a.size == 32.5 },
      describing: "after 32,5: size \(model.comparison.a.size); \(describe(field, in: host))")
    #expect(model.comparison.b?.size == 32.5)
    #expect(model.comparison.link?.sizeRatio == 1)
    try await host.submit("invalid", to: field)
    try await host.settle(
      until: { field.stringValue == "32,5" },
      describing: "after invalid: \(describe(field, in: host))")
    #expect(model.comparison.a.size == 32.5)
    host.setContent(
      WorkbenchView(model: model).environment(\.locale, Locale(identifier: "en_US")))
    try await host.settle(
      until: { field.stringValue == "32.5" },
      describing: "after en_US: \(describe(field, in: host))")
  }

  private func describe<Content>(_ field: NSTextField, in host: WorkbenchTestHost<Content>)
    -> String
  {
    let sizes = host.subviews.compactMap { $0 as? NSTextField }.filter {
      $0.placeholderString == "Size" || $0.placeholderString == "Mixed"
    }.map { "\($0.stringValue.debugDescription)@\(Int($0.convert($0.bounds, to: host.view).minX))" }
    let frame = field.convert(field.bounds, to: host.view)
    return
      "field \(field.stringValue.debugDescription) at \(frame), editing \(field.currentEditor() != nil), "
      + "window \(host.window.frame), size fields \(sizes)"
  }

  @Test(arguments: [480.0, 900.0])
  func inspectorTypographyAndDisclosureControlsChangeOnlyTheirOwnSide(height: Double) async throws {
    let model = WorkbenchModel(comparison: Comparison(a: .init("ArialMT")))
    let originalB = model.comparison.b
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 246, height: height)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Kerning")
    try await host.settle { model.comparison.a.features["ot.kern"] == 0 }
    #expect(model.comparison.a.features["ot.kern"] == 0)
    try await host.press("Kerning")
    try await host.settle { model.comparison.a.features["ot.kern"] != 0 }
    #expect(model.comparison.a.features["ot.kern"] != 0)
    let scroll = try #require(host.subviews.compactMap { $0 as? NSScrollView }.first)
    let document = try #require(scroll.documentView)
    let expandedHeight = document.frame.height
    try await host.press("Common")
    try await host.settle { document.frame.height < expandedHeight }
    let collapsedHeight = document.frame.height
    #expect(collapsedHeight < expandedHeight)
    try await host.press("Common")
    try await host.settle { document.frame.height > collapsedHeight }
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
    try await host.settle {
      model.comparison.a.size > 22 && model.comparison.b?.size == model.comparison.a.size
    }
    #expect(model.comparison.a.size > 22)
    #expect(model.comparison.b?.size == model.comparison.a.size)
    let axis = try #require(model.comparison.a.face.axes.first { $0.tag == "wdth" })
    let initial = model.comparison.a.axes[axis.id]
    try await host.incrementSlider("Font A \(axis.name)", title: axis.name)
    try await host.settle { model.comparison.a.axes[axis.id] != initial }
    #expect(model.comparison.a.axes[axis.id] != initial)
  }

  @Test func workbenchToolbarCanHideAndRestoreBothInspectors() async throws {
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel()))
    defer { host.window.close() }
    try await host.settle()
    for side in ["A", "B"] {
      try await host.press("Toggle font \(side) inspector")
      try await host.settle {
        !host.elements.contains { $0.accessibilityLabel?() == "Font \(side) family" }
      }
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
    try await host.settle { model.comparison.a.postScriptName != original }
    #expect(model.comparison.a.postScriptName != original)
    let samples = Sample.allCases.map(\.title)
    try await host.choose("Sample", nativeTitles: samples, item: Sample.alphabet.title)
    try await host.choose("Sample", nativeTitles: samples, item: Sample.reading.title)
    try await host.settle { model.comparison.sample == .reading }
    #expect(model.comparison.sample == .reading)
    for sample in [Sample.alphabet, .numerals] {
      try await host.choose("Sample", nativeTitles: samples, item: sample.title)
      try await host.settle { model.comparison.sample == sample }
      #expect(model.comparison.sample == sample)
    }
    try await host.choose("Sample", nativeTitles: samples, item: Sample.custom.title)
    try await host.settle { !host.window.sheets.isEmpty }
    #expect(!host.window.sheets.isEmpty)
    try await host.press("Cancel")
    try await host.settle { host.window.sheets.isEmpty }
    #expect(model.comparison.sample == .numerals)
  }

  @Test func rankedCharacterButtonsSwitchToGlyphInspection() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    let inspectButton: () -> AnyObject? = {
      func isRankedButton(_ element: AnyObject) -> Bool {
        (element.accessibilityLabel?() ?? "").hasPrefix("Inspect U+")
      }
      return host.elements.first(where: isRankedButton)
        ?? host.hitElements.first(where: isRankedButton)
    }
    try await host.settle(
      until: { inspectButton() != nil }, describing: "no ranked character button")
    let button = try #require(inspectButton())
    let help = try #require(button.accessibilityHelp?())
    #expect(help.contains("\nShape "))
    #expect(help.contains("\nSpacing "))
    #expect(help.contains("\nFrequency "))
    // The weight line has its own " · ", so only the name section is checked.
    let nameSection = try #require(help.components(separatedBy: "\nShape").first)
    #expect(!nameSection.contains(" · ") && !nameSection.contains("#"))
    #expect(help.contains(" · weight "))
    #expect(button.accessibilityPerformPress?() == true)
    try await host.settle { model.comparison.mode == .glyph }
    #expect(model.comparison.mode == .glyph)
  }

  private func characterField<Content>(_ host: WorkbenchTestHost<Content>) -> NSTextField? {
    host.subviews.compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Character" }
  }

  private func fieldScalars<Content>(_ host: WorkbenchTestHost<Content>) -> [Unicode.Scalar]? {
    characterField(host).map { Array($0.stringValue.unicodeScalars) }
  }

  private func glyphCanvasLabel<Content>(_ host: WorkbenchTestHost<Content>) -> String? {
    host.subviews.lazy.compactMap { $0 as? GlyphDrawingView }.first?.accessibilityLabel()
  }

  private func installedFontsSearch<Content>(_ host: WorkbenchTestHost<Content>) -> NSTextField? {
    host.subviews.compactMap { $0 as? NSTextField }.first {
      $0.placeholderString == "Search installed fonts"
    }
  }

  private func sheetEditor<Content>(_ host: WorkbenchTestHost<Content>) -> NSTextView? {
    host.subviews.compactMap { $0 as? NSTextView }.first {
      $0.isEditable && !$0.isFieldEditor && $0.window?.sheetParent === host.window
    }
  }
}

@MainActor final class WorkbenchTestHost<Content: View> {
  let window: WorkbenchTestWindow
  let view: NSHostingView<AnyView>
  private var menuSelection: WorkbenchTestMenuSelection?

  init(_ content: Content, width: Double = 1440, height: Double = 900) {
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

  func settle(
    until condition: () -> Bool, describing state: @autoclosure () -> String = "",
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    try await settle()
    try await waitUntil(
      condition, describing: state(), step: { try await self.settle() },
      sourceLocation: sourceLocation)
  }

  func element(_ label: String, timeout: Duration = .seconds(10)) async throws -> AnyObject {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if let result = try await find(label, until: deadline) { return result }
      if ContinuousClock.now < deadline { try await settle() }
    }
    throw MissingControl(label: label, available: accessibilitySummary)
  }

  private func find(_ label: String, until deadline: ContinuousClock.Instant) async throws
    -> AnyObject?
  {
    if let result = visibleElement(label, until: deadline) { return result }
    // Older SwiftUI versions expose only the visible portion of a scroll view.
    for scroll in subviews.compactMap({ $0 as? NSScrollView }) {
      guard ContinuousClock.now < deadline else { return nil }
      guard let document = scroll.documentView else { continue }
      let original = scroll.contentView.bounds.origin
      let maximum = document.bounds.height - scroll.contentView.bounds.height
      guard maximum > 0 else { continue }
      let step = max(1, scroll.contentView.bounds.height / 2)
      for offset in stride(from: 0, through: maximum + step, by: step) {
        guard ContinuousClock.now < deadline else { break }
        scroll.contentView.scroll(to: NSPoint(x: original.x, y: min(offset, maximum)))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle()
        if let result = visibleElement(label, until: deadline) { return result }
      }
      scroll.contentView.scroll(to: original)
      scroll.reflectScrolledClipView(scroll.contentView)
      if ContinuousClock.now < deadline { try await settle() }
    }
    return nil
  }

  private var accessibilitySummary: String {
    var named = Set<String>()
    var unnamed: [String: Int] = [:]
    var seen = Set<ObjectIdentifier>()
    let deadline = ContinuousClock.now + .seconds(1)
    let snapshot =
      elements + hitElements(until: deadline) + finelySampledHitElements(until: deadline)
    let samplingTimedOut = ContinuousClock.now >= deadline
    // hitElements returns an element once per sample point that lands on it.
    for element in snapshot
    where seen.insert(ObjectIdentifier(element)).inserted {
      let role = element.accessibilityRole?()?.rawValue ?? "no role"
      let names = [
        element.accessibilityIdentifier?(), element.accessibilityLabel?(),
        element.accessibilityTitle?(),
      ].compactMap { $0 }.filter { !$0.isEmpty }
      if names.isEmpty {
        unnamed[role, default: 0] += 1
      } else {
        named.insert("\(role) \(names.joined(separator: "/"))")
      }
    }
    let unnamedCounts = unnamed.sorted { $0.key < $1.key }.map { "\($0.key) x\($0.value)" }
    let scrolls = subviews.compactMap { $0 as? NSScrollView }.map {
      let bounds = $0.contentView.bounds
      return "document \($0.documentView?.frame.height ?? 0), viewport \(bounds.height), "
        + "offset \(bounds.origin.y)"
    }
    return
      "\(named.sorted().joined(separator: ", ")). Unnamed: \(unnamedCounts.joined(separator: ", ")). "
      + "Scroll views: \(scrolls.joined(separator: "; "))"
      + (samplingTimedOut ? ". Hit-test sampling reached its deadline" : "")
  }

  private func visibleElement(_ label: String, until deadline: ContinuousClock.Instant? = nil)
    -> AnyObject?
  {
    func matches(_ element: AnyObject) -> Bool {
      element.accessibilityIdentifier?() == label || element.accessibilityLabel?() == label
        || element.accessibilityTitle?() == label
    }
    return elements.first(where: matches) ?? hitElements(until: deadline).first(where: matches)
      ?? finelySampledHitElements(until: deadline).first(where: matches)
  }

  func isEnabled(_ label: String) -> Bool {
    visibleElement(label)?.isAccessibilityEnabled?() == true
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

  func incrementSlider(_ label: String, between leading: String, and trailing: String)
    async throws
  {
    let sliders = subviews.compactMap { $0 as? NSSlider }
    guard !sliders.isEmpty else {
      _ = try await element(label).accessibilityPerformIncrement?()
      return
    }
    // Older SwiftUI omits the native sliders' AX names. The labeled controls on
    // either side of the slider identify it.
    let before = try #require(try await element(leading).accessibilityFrame?())
    let after = try #require(try await element(trailing).accessibilityFrame?())
    let matches = sliders.filter { slider in
      guard let owner = slider.window else { return false }
      let frame = owner.convertToScreen(slider.convert(slider.bounds, to: nil))
      return frame.minX >= before.maxX && frame.maxX <= after.minX
        && frame.minY < before.maxY && frame.maxY > before.minY
        && frame.minY < after.maxY && frame.maxY > after.minY
    }
    try #require(matches.count == 1, "Expected one slider between \(leading) and \(trailing)")
    _ = matches[0].accessibilityPerformIncrement()
  }

  func choose(
    _ label: String, nativeTitles: [String], item: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
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
    #expect(control.accessibilityPerformPress?() == true, sourceLocation: sourceLocation)
    try await waitUntil(
      { selection.completed }, describing: "Menu selection did not complete: \(label)",
      sourceLocation: sourceLocation)
    try #require(selection.completed, sourceLocation: sourceLocation)
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

  func submit(_ value: String, to field: NSTextField) async throws {
    enter(value, in: field)
    try await settle()
    let editor = try #require(field.currentEditor(), "The field is not being edited")
    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
  }

  private var contentRoots: [NSView] {
    [view]
      + (window.sheets + (window.childWindows ?? [])
      + NSApp.windows.filter {
        $0.isVisible && String(describing: type(of: $0)).contains("Popover")
      }).compactMap(\.contentView)
  }

  var hitElements: [AnyObject] {
    hitElements(until: nil)
  }

  private func hitElements(until deadline: ContinuousClock.Instant?) -> [AnyObject] {
    var result: [AnyObject] = []
    for root in contentRoots {
      guard let owner = root.window else { continue }
      // Small native controls can fall between the fallback grid's sample points.
      for view in descendants(of: root) where view is NSControl {
        if let deadline, ContinuousClock.now >= deadline { return result }
        let frame = owner.convertToScreen(view.convert(view.bounds, to: nil))
        if let hit = root.accessibilityHitTest(NSPoint(x: frame.midX, y: frame.midY)) {
          result.append(hit as AnyObject)
        }
      }
      result += sampledHits(in: root, rowStep: 16, until: deadline)
    }
    return result
  }

  // A 15-point row can fall between sample rows 16 points apart.
  private func finelySampledHitElements(until deadline: ContinuousClock.Instant?) -> [AnyObject] {
    contentRoots.flatMap { sampledHits(in: $0, rowStep: 4, until: deadline) }
  }

  private func sampledHits(
    in root: NSView, rowStep: Double, until deadline: ContinuousClock.Instant?
  )
    -> [AnyObject]
  {
    guard let owner = root.window else { return [] }
    var result: [AnyObject] = []
    let bounds = owner.convertToScreen(root.convert(root.bounds, to: nil))
    for y in stride(from: bounds.minY + 8, to: bounds.maxY, by: rowStep) {
      for x in stride(from: bounds.minX + 8, to: bounds.maxX, by: 16) {
        if let deadline, ContinuousClock.now >= deadline { return result }
        if let hit = root.accessibilityHitTest(NSPoint(x: x, y: y)) {
          result.append(hit as AnyObject)
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
