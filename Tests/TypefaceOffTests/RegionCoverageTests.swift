import AppKit
import CoreGraphics
import CoreText
import SwiftUI
import Synchronization
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct RegionCoverageTests {
  @Test func oldLanguageProgressCannotReplaceTheCurrentFontCoverage() async throws {
    typealias Progress = @Sendable ([String: LanguageCoverage]) async -> Void
    let oldProgress = Mutex<Progress?>(nil)
    let oldCompletion = Mutex<CheckedContinuation<Void, Never>?>(nil)
    let database = LanguageDatabase.shared
    let language = try #require(database.languages.first)
    let engine = LanguageCoverageEngine()
    let currentFont = FontConfiguration("ArialMT")
    let ready = try await engine.results(for: database.languages, font: currentFont)
    let browser = LanguageBrowserModel(
      load: { database },
      check: { _, font, _, progress in
        if font.postScriptName == "HelveticaNeue" {
          oldProgress.withLock { $0 = progress }
          await withCheckedContinuation { continuation in
            oldCompletion.withLock { $0 = continuation }
          }
        } else {
          await progress(ready)
        }
      })
    let old = Task {
      await browser.update(.init(Comparison(a: .init("HelveticaNeue"), b: nil)))
    }
    try await waitUntil { oldCompletion.withLock { $0 != nil } }
    await browser.update(.init(Comparison(a: currentFont, b: nil)))
    let progress = try #require(oldProgress.withLock { $0 })
    await progress([:])
    let completion = try #require(
      oldCompletion.withLock { value in
        let result = value
        value = nil
        return result
      })
    completion.resume()
    await old.value
    #expect(browser.a[language.id] != nil && browser.a.count == ready.count)
    #expect(browser.b.isEmpty && !browser.checking && browser.problem == nil)
  }

  @Test func aFailedPreparationStopsRankingWithoutCancellingItsConsumer() async {
    let comparison = Comparison()
    let preparation = PreparedSearch<Comparison, [GlyphDifference]>(input: comparison) { _ in
      throw CancellationError()
    }
    let ranking = RankingModel(preparedRanking: preparation)
    await ranking.update(comparison)
    #expect(!ranking.comparing && ranking.scores.isEmpty && !Task.isCancelled)
  }

  @Test func aStaleCharacterAnswerDoesNotReplaceTheEmptyQueryHint() async throws {
    let search = CharacterSearchModel(load: CharacterSearchPickerTests.canned)
    let comparison = Comparison()
    var chosen: [String] = []
    let host = WorkbenchTestHost(
      CharacterSearchPicker(comparison: comparison, search: search) { chosen.append($0) },
      width: 440, height: 460)
    defer { host.window.close() }
    try await host.settle()
    await search.update(.init(query: "arrow", fonts: [comparison.a]))
    try await host.settle()
    #expect(search.answer?.request.query == "arrow" && chosen.isEmpty)
    _ = try await host.element("Character search hint")
  }
  @Test(arguments: [false, true])
  func obsoleteFamilyCompletionCannotChangeTheCurrentRequest(fail: Bool) async throws {
    let (stream, continuation) = AsyncThrowingStream<FamilySimilarity, Error>.makeStream()
    let model = FamilySimilarityModel { _, _, _ in stream }
    model.sort = .similarity
    let request = FamilySimilarityModel.Request(reference: .init("ArialMT"), scale: 2)
    let old = Task { await model.update(request, catalog: FontCatalog()) }
    try await waitUntil { model.comparing }
    await model.update(nil, catalog: FontCatalog())
    if fail {
      continuation.finish(throwing: SimilarityError.renderingFailed)
    } else {
      continuation.finish()
    }
    await old.value
    #expect(model.results.isEmpty && model.error == nil && !model.comparing)
  }

  @Test func aStoppedFitCannotPublishALateLoaderFailure() async throws {
    let pending = Mutex<CheckedContinuation<AsyncThrowingStream<FontFitResult, Error>, Error>?>(nil)
    let fit = FontFitModel { _, _ in
      try await withCheckedThrowingContinuation { continuation in
        pending.withLock { $0 = continuation }
      }
    }
    let config = FontConfiguration("ArialMT")
    fit.start(.init(a: config, b: config, text: "a", options: .init(config: config), scale: 2))
    try await waitUntil { pending.withLock { $0 != nil } }
    let stopped = try #require(fit.stop())
    let continuation = try #require(
      pending.withLock { value in
        let result = value
        value = nil
        return result
      })
    continuation.resume(throwing: SimilarityError.renderingFailed)
    await stopped.value
    #expect(fit.error == nil && fit.result == nil && !fit.running)
  }

  @Test func programmaticSearchTextUpdatesTheNativeField() async throws {
    func picker(_ text: String) -> PickerSearchField {
      PickerSearchField(
        label: "Region search", text: .constant(text), move: { _ in },
        submit: {}, cancel: {})
    }
    let host = WorkbenchTestHost(picker("initial"))
    defer { host.window.close() }
    try await host.settle()
    let field = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
    #expect(field.stringValue == "initial")
    host.setContent(picker("replacement"))
    try await host.settle { field.stringValue == "replacement" }
    picker("unchanged").makeCoordinator().controlTextDidChange(
      Notification(name: NSControl.textDidChangeNotification, object: NSObject()))
    #expect(field.stringValue == "replacement")
  }

  @Test func detachingASearchFieldPreservesItsQueryAndReleasesTheWindow() async throws {
    var query = "Retained query"
    let host = WorkbenchTestHost(
      PickerSearchField(
        label: "Detachment search", text: Binding(get: { query }, set: { query = $0 }),
        move: { _ in }, submit: {}, cancel: {}))
    defer { host.window.close() }
    try await host.settle()
    let field = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
    #expect(field.window === host.window && field.stringValue == query)
    field.removeFromSuperview()
    #expect(field.window == nil)
    #expect(field.stringValue == "Retained query" && query == "Retained query")
  }

  @Test func repeatedMissingFontNamesRemainVisibleInDisambiguatedRows() {
    let missing = FontConfiguration("TypefaceOff-Missing-Region-Fixture")
    #expect(
      CharacterSearchRow.names(of: [missing, missing]) == [
        missing.postScriptName, missing.postScriptName,
      ])
  }

  @Test func anAbsentCurrentFamilySelectsTheFirstAvailableFamily() async throws {
    var selected: String?
    let host = WorkbenchTestHost(
      FontFamilyPicker(
        families: ["Arial", "Helvetica Neue"], currentFamily: "Missing",
        allowsNone: false, choose: { selected = $0 }),
      width: 300, height: 400)
    defer { host.window.close() }
    try await host.settle()
    let search = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(selected == "Arial")
  }

  @Test func anOpticalSizeAxisExposesItsDefaultValue() async throws {
    let url = try #require(
      Bundle(for: RegionFixtureBundle.self).url(forResource: "OpticalSize", withExtension: "ttf"))
    try #require(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
    defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
    let config = FontConfiguration("TypefaceOffRegionOptical-Regular")
    let axis = try #require(config.face.axes.first { $0.tag == "opsz" })
    #expect(FontRenderer.isAvailable(config))
    let model = WorkbenchModel(comparison: Comparison(a: config, b: nil))
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 400, height: 800)
    defer { host.window.close() }
    try await host.settle()
    let field = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first {
        $0.placeholderString == axis.name
      })
    #expect(field.doubleValue == axis.defaultValue)
  }

  @Test func opticalSizeAndSectionResetsAgreeAboutDefaults() throws {
    let url = try #require(
      Bundle(for: RegionFixtureBundle.self).url(forResource: "OpticalSize", withExtension: "ttf"))
    try #require(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
    defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
    var comparison = Comparison(a: .init("TypefaceOffRegionOptical-Regular"), b: nil)
    let catalog = FontCatalog()
    let axis = SpecificationSetting.axis(tagNumber("opsz"))
    comparison.a.size = 44
    #expect(axis.isChanged(in: comparison.a))
    axis.reset(in: &comparison, catalog: catalog)
    #expect(comparison.a.axes[tagNumber("opsz")] == 44)
    #expect(!axis.isChanged(in: comparison.a))
    comparison.resetAppearance(catalog: catalog)
    #expect(comparison.a.size == 22 && comparison.a.axes[tagNumber("opsz")] == 22)
    #expect(!comparison.hasAppearanceChanges(catalog: catalog))
    #expect(!axis.isChanged(in: comparison.a))
  }

  @Test func missingCharactersRemainExplicitInsideEmphasizedPassages() {
    let content = SpecimenText.makeContent(
      config: .init("NotoSansSyriac-Regular"), text: Sample.reading.text, sample: .reading)
    #expect(content.spans.contains { !$0.supported })
    for span in content.spans where !span.supported {
      #expect(content.text.attributedSubstring(from: span.range).string.hasPrefix("[U+"))
    }
  }

  @Test func staleSpansAndDetachedLayoutDoNotProduceHighlightsOrTooltips() throws {
    let view = SpecimenNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    view.textStorage?.setAttributedString(
      NSAttributedString(string: "a", attributes: FontRenderer.attributes(.init("ArialMT"))))
    view.spans = [.init(range: NSRange(location: 0, length: 99), glyph: "a", supported: true)]
    view.highlights = ["a"]
    view.ensureSpecimenLayout()
    view.refreshHighlights()
    view.refreshToolTips()
    let layout = try #require(view.layoutManager)
    #expect(
      layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil)
    #expect(view.trackingAreas.allSatisfy { $0.options.contains(.inVisibleRect) })
    layout.removeTextContainer(at: 0)
    view.refreshHighlights()
    #expect(view.view(view, stringForToolTip: 0, point: .zero, userData: nil).isEmpty)
  }

  @Test func whitespaceBesideAGlyphHasNoTooltip() throws {
    let config = FontConfiguration("ArialMT")
    let content = SpecimenText.makeContent(config: config, text: "a")
    let view = SpecimenNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    view.textStorage?.setAttributedString(content.text)
    view.spans = content.spans
    view.ensureSpecimenLayout()
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    let bounds = layout.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
    let point = NSPoint(
      x: view.textContainerOrigin.x + bounds.minX - 1,
      y: view.textContainerOrigin.y + bounds.midY)
    #expect(view.view(view, stringForToolTip: 0, point: point, userData: nil).isEmpty)
  }

  @Test func theSpecimenAdapterToleratesARemovedDocumentView() async throws {
    var config = FontConfiguration("ArialMT")
    let host = WorkbenchTestHost(SpecimenText(config: config, text: "a"))
    defer { host.window.close() }
    try await host.settle()
    let scroll = try #require(host.subviews.compactMap { $0 as? SpecimenScrollView }.first)
    scroll.documentView = nil
    config.size = 30
    host.setContent(SpecimenText(config: config, text: "b"))
    try await host.settle()
    #expect(scroll.documentView == nil)
  }

  @Test func duplicateAttachmentAndShortScrollingPreserveThePartnersPosition() {
    let position = SpecimenScrollPosition()
    func scroll(height: Double) -> NSScrollView {
      let result = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
      result.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: height))
      return result
    }
    let long = scroll(height: 1200)
    let short = scroll(height: 100)
    position.attach(long)
    position.attach(long)
    position.attach(short)
    long.contentView.scroll(to: NSPoint(x: 0, y: 500))
    NotificationCenter.default.post(
      name: NSView.boundsDidChangeNotification, object: long.contentView)
    let origin = long.contentView.bounds.origin
    NotificationCenter.default.post(
      name: NSView.boundsDidChangeNotification, object: short.contentView)
    #expect(long.contentView.bounds.origin == origin)
    weak var released: NSScrollView?
    let retainedClip = autoreleasepool {
      let temporary = scroll(height: 1000)
      released = temporary
      let clip = temporary.contentView
      position.attach(temporary)
      temporary.contentView = NSClipView()
      return clip
    }
    #expect(released == nil)
    NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: retainedClip)
    NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: retainedClip)
    position.reset()
    #expect(long.contentView.bounds.minY == 0)
  }

  @Test func detachedUndoBridgesAndUnpairedEditEndingsLeaveStateUnchanged() async {
    let bridge = WindowUndoManager.Bridge()
    bridge.viewDidMoveToWindow()
    #expect(bridge.manager.wrappedValue == nil)
    let model = WorkbenchModel()
    let original = model.comparison
    let undo = UndoManager()
    model.endContinuousEdit(undoManager: undo)
    #expect(model.comparison == original && !undo.canUndo)
  }

  @Test func defaultCanvasCallbacksAndLeftNavigationRemainUsable() async throws {
    let canvas = GlyphDrawingView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    _ = canvas.becomeFirstResponder()
    await Task.yield()
    var directions: [Int] = []
    canvas.navigate = { directions.append($0) }
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}",
        isARepeat: false, keyCode: 123))
    canvas.keyDown(with: event)
    #expect(directions == [-1])
    let scroll = GlyphScrollView()
    scroll.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    scroll.smartMagnify(with: event)
    #expect(scroll.magnification == 2)
  }

  @Test func invertedWheelDirectionReversesZoomWithoutChangingTheCanvasFrame() {
    let scroll = GlyphScrollView()
    scroll.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    scroll.setZoom(3)
    let frame = scroll.canvas.frame
    scroll.scrollWheel(with: InvertedRegionWheel())
    #expect(abs(scroll.magnification - 3 / pow(1.1, 3)) < 0.000001)
    #expect(scroll.canvas.frame == frame)
  }

  @Test func theSelectedDifferenceRemainsHighlightedWhileTheCanvasHasFocus() async throws {
    var comparison = Comparison()
    comparison.mode = .glyph
    let model = WorkbenchModel(comparison: comparison)
    let scores = try #require(try await model.initialWork.ranking.value(for: comparison))
    let first = try #require(
      Differences.ranked(scores, shape: true, spacing: false, frequency: true).first)
    model.updatePresentation { $0.selectedGlyph = first.glyph }
    let window = RegionFocusWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(
      rootView: WorkbenchView(model: model).environment(\.appearsActive, true)
        .environment(\.accessibilityEnabled, true))
    host.sceneBridgingOptions = .all
    window.contentView = host
    window.orderFront(nil)
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap { descendants($0) }
    }
    try await waitUntil {
      host.layoutSubtreeIfNeeded()
      return descendants(host).contains { $0 is GlyphDrawingView }
    }
    let canvas = try #require(descendants(host).compactMap { $0 as? GlyphDrawingView }.first)
    canvas.requestFocus(UUID())
    try await waitUntil { canvas.hasKeyboardFocus }
    try await Task.sleep(for: .milliseconds(300))
    host.layoutSubtreeIfNeeded()
    #expect(model.comparison.mode == .glyph)
    #expect(model.comparison.selectedGlyph == first.glyph)
    #expect(canvas.hasKeyboardFocus)
  }

  @Test func invalidOverlayDimensionsLeaveTheDestinationUntouched() throws {
    let context = try #require(
      CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    GlyphOverlay.draw(
      [255], [0], width: 0, height: 1, context: context,
      rect: CGRect(x: 0, y: 0, width: 4, height: 4))
    let bytes = try #require(context.data)
    #expect(UnsafeRawBufferPointer(start: bytes, count: 64).allSatisfy { $0 == 0 })
  }
}

private final class RegionFixtureBundle: NSObject {}

@MainActor private final class RegionFocusWindow: NSWindow {
  override var isKeyWindow: Bool { true }
}

private final class InvertedRegionWheel: NSEvent {
  override var isDirectionInvertedFromDevice: Bool { true }
  override var hasPreciseScrollingDeltas: Bool { false }
  override var scrollingDeltaY: CGFloat { 3 }
  override var locationInWindow: NSPoint { .zero }
}
