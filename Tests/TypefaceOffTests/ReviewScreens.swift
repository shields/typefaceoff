import AppKit
import ScreenCaptureKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct ReviewScreens {
  @Test(
    .enabled(if: !(ProcessInfo.processInfo.environment["TYPEFACEOFF_REVIEW_DIR"] ?? "").isEmpty))
  func benchmarkGlyphGestures() throws {
    let folder = try #require(ProcessInfo.processInfo.environment["TYPEFACEOFF_REVIEW_DIR"])
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    let scroll = GlyphScrollView()
    scroll.setFrameSize(NSSize(width: 1000, height: 600))
    scroll.layoutSubtreeIfNeeded()
    var comparison = Comparison()
    comparison.selectedGlyph = "@"
    scroll.canvas.update(comparison)
    var timings: [String: Double] = [:]
    for zoom in [1.0, 2.0, 4.0, 8.0] {
      scroll.setZoom(zoom)
      let start = ContinuousClock.now
      for _ in 0..<8 {
        scroll.pan(by: NSSize(width: 3, height: 2))
        let rect = scroll.canvas.visibleRect
        let bitmap = try #require(scroll.canvas.bitmapImageRepForCachingDisplay(in: rect))
        scroll.canvas.cacheDisplay(in: rect, to: bitmap)
      }
      let duration = start.duration(to: .now).components
      timings["\(Int(zoom * 100))% draw milliseconds"] =
        (Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15) / 8
    }
    let maskStart = ContinuousClock.now
    let mask = FontRenderer.mask(
      "@", config: comparison.a, size: 600, width: 2000, height: 1200,
      origin: CGPoint(x: 500, y: 200))
    let maskDuration = maskStart.duration(to: .now).components
    timings["Mask milliseconds"] =
      Double(maskDuration.seconds) * 1000 + Double(maskDuration.attoseconds) / 1e15
    let compositeStart = ContinuousClock.now
    let pixels = GlyphOverlay.pixels(mask, mask)
    let compositeDuration = compositeStart.duration(to: .now).components
    timings["Composite milliseconds"] =
      Double(compositeDuration.seconds) * 1000 + Double(compositeDuration.attoseconds) / 1e15
    #expect(pixels.count == mask.count * 4)
    try JSONSerialization.data(withJSONObject: timings, options: [.prettyPrinted, .sortedKeys])
      .write(to: URL(fileURLWithPath: folder).appendingPathComponent("glyph-performance.json"))
  }

  @Test(
    .enabled(if: !(ProcessInfo.processInfo.environment["TYPEFACEOFF_REVIEW_DIR"] ?? "").isEmpty))
  func renderWorkbench() async throws {
    let folder = try #require(ProcessInfo.processInfo.environment["TYPEFACEOFF_REVIEW_DIR"])
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    NSApplication.shared.activate()
    var glyph = Comparison()
    glyph.mode = .glyph
    glyph.selectedGlyph = "@"
    var single = glyph
    single.b = nil
    var spacing = glyph
    spacing.shape = false
    spacing.spacing = true
    var cases: [(String, Double, Comparison)] = [
      ("text", 1440, Comparison()), ("glyph", 1280, glyph), ("single", 1280, single),
      ("spacing", 1280, spacing),
      ("text-960", 960, Comparison()), ("text-1280", 1280, Comparison()),
      ("glyph-1440", 1440, glyph),
      ("glyph-zoom", 1280, glyph), ("single-zoom", 1280, single),
      ("single-text", 1280, Comparison(b: nil)),
    ]
    var languages = Comparison()
    languages.mode = .languages
    cases.append(("languages", 1440, languages))
    cases.append(("languages-1280", 1280, languages))
    languages.b = nil
    cases.append(("languages-single", 1280, languages))
    var both = glyph
    both.spacing = true
    cases.append(("both-differences", 1280, both))
    var neither = glyph
    neither.shape = false
    cases.append(("no-highlights", 1280, neither))
    var frequencyOn = Comparison()
    frequencyOn.spacing = true
    cases.append(("frequency-on", 1280, frequencyOn))
    var frequencyOff = frequencyOn
    frequencyOff.frequency = false
    cases.append(("frequency-off", 1280, frequencyOff))
    var rankedSpacing = Comparison()
    rankedSpacing.shape = false
    rankedSpacing.spacing = true
    cases.append(("spacing-ranked", 1280, rankedSpacing))
    var missing = Comparison()
    missing.sample = .custom
    missing.customText = "Missing characters stay identifiable: 🦄 🦄 👩‍🚀."
    cases.append(("missing-characters", 1280, missing))
    missing.b = .init("TypefaceOff-Does-Not-Exist")
    cases.append(("missing-font", 1280, missing))
    for sample in [Sample.reading, .alphabet, .numerals] {
      var comparison = Comparison()
      comparison.sample = sample
      cases.append((sample.rawValue, 1440, comparison))
    }
    var smallText = Comparison()
    smallText.a.size = 14
    smallText.b?.size = 14
    cases.append(("small-text", 1440, smallText))
    var leading = Comparison()
    leading.a.leading = 30
    leading.b?.leading = 38
    leading.calibrate()
    cases.append(("leading", 1440, leading))
    var syriac = Comparison(a: .init("NotoSansSyriac-Regular"), b: nil)
    syriac.mode = .glyph
    syriac.selectedGlyph = "ܐ"
    cases.append(("syriac", 1280, syriac))
    let catalog = FontCatalog()
    let skiaFace = try #require(catalog.preferredFace(in: "Skia"))
    var skia = Comparison(a: .init(skiaFace.id), b: .init(skiaFace.id))
    skia.a.axes[tagNumber("wdth")] = 0.75
    skia.b?.axes[tagNumber("wdth")] = 1.25
    cases.append(("skia", 1440, skia))
    if let inter = catalog.preferredFace(in: "Inter Variable"),
      let atkinson = catalog.preferredFace(in: "Atkinson Hyperlegible Next")
    {
      var variable = Comparison(a: .init(inter.id), b: .init(atkinson.id))
      variable.mode = .glyph
      variable.a.features["ot.cv11"] = 1
      cases.append(("variable", 1440, variable))
    }
    for (name, width, comparison) in cases {
      let height = width == 1440 ? 900.0 : 800.0
      let model = WorkbenchModel(comparison: comparison)
      if comparison.mode == .languages { model.languages.selection = "eng" }
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let host = NSHostingView(
        rootView: WorkbenchView(model: model))
      host.sizingOptions = []
      host.sceneBridgingOptions = .all
      window.contentView = host
      window.setContentSize(NSSize(width: width, height: height))
      window.makeKeyAndOrderFront(nil)
      try await Task.sleep(for: .milliseconds(name == "variable" ? 2000 : 750))
      if comparison.mode == .languages {
        try await waitUntil({ !model.languages.checking && model.languages.selectedLanguage != nil }
        )
      } else if comparison.b.map(FontRenderer.isAvailable) == true
        && (comparison.shape || comparison.spacing)
      {
        try await waitUntil({
          guard let document = differenceStrip(in: host)?.documentView else { return false }
          return document.bounds.width > DifferenceStripView.fadeWidth
        })
      }
      host.layoutSubtreeIfNeeded()
      if name.hasSuffix("-zoom"), let scroll = glyphScroll(in: host) {
        scroll.setZoom(2)
        scroll.zoomChanged(2)
        try await Task.sleep(for: .milliseconds(100))
      }
      try save(host, as: name, in: folder)
      #expect(abs(host.bounds.width - width) < 0.5)
      #expect(abs(host.bounds.height - height) < 0.5)
      if name == "text" {
        try await saveTextWindow(window, in: folder)
      }
      window.close()
    }
    let match = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled],
      backing: .buffered, defer: false)
    match.isReleasedWhenClosed = false
    var matching = Comparison()
    matching.sample = .custom
    matching.customText = "Hamburg minimum AV To fi fl 1820"
    let fit = FontFitModel()
    let host = NSHostingView(
      rootView: WorkbenchView(model: WorkbenchModel(comparison: matching), fit: fit, matching: true)
        .preferredColorScheme(.light))
    match.contentView = host
    match.orderFront(nil)
    try await waitUntil({
      (differenceStrip(in: host)?.documentView?.bounds.width ?? 0) > DifferenceStripView.fadeWidth
    })
    try save(host, as: "match", in: folder)
    match.close()
    fit.stop()
    let ranking = FamilySimilarityModel()
    ranking.sort = .similarity
    let picker = WorkbenchTestHost(
      FontFamilyPicker(
        families: catalog.families, currentFamily: "Arial",
        allowsNone: true, ranking: ranking, reference: .init("HelveticaNeue"), catalog: catalog,
        choose: { _ in }), width: 300, height: 400)
    let deadline = ContinuousClock.now + .seconds(240)
    repeat {
      try await picker.settle()
    } while (ranking.results.isEmpty || ranking.comparing) && ranking.error == nil
      && ContinuousClock.now < deadline
    try #require(
      ranking.error == nil && !ranking.comparing && ranking.results["Arial"]?.score != nil)
    let table = try #require(picker.subviews.compactMap { $0 as? NSTableView }.first)
    table.scrollRowToVisible(0)
    try await picker.settle()
    try save(picker.view, as: "similarity-picker", in: folder)
    picker.window.close()
    let searchModel = CharacterSearchModel(load: CharacterSearch.results(for:fonts:))
    let search = WorkbenchTestHost(
      CharacterSearchPicker(comparison: Comparison(), search: searchModel) { _ in },
      width: 440, height: 460)
    try await search.settle()
    search.enter(
      "arrow", in: try #require(search.subviews.compactMap { $0 as? NSSearchField }.first))
    try await search.settle(until: {
      searchModel.answer?.request.query == "arrow" && searchModel.answer?.results.isEmpty == false
    })
    try save(search.view, as: "character-search", in: folder)
    search.window.close()

    let model = WorkbenchModel()
    let inspector = WorkbenchTestHost(
      ComparisonInspector(model: model, state: model.inspector).preferredColorScheme(.light),
      width: 320, height: 680)
    try await inspector.settle()
    try save(inspector.view, as: "inspector", in: folder)
    model.inspector.reveal(.typography)
    try await inspector.settle(until: { model.inspector.scrollOffset > 0 })
    try save(inspector.view, as: "typography", in: folder)
    inspector.window.close()
  }

  private func saveTextWindow(_ window: NSWindow, in folder: String) async throws {
    let content = try await SCShareableContent.currentProcess
    let source = try #require(content.windows.first { $0.windowID == window.windowNumber })
    let filter = SCContentFilter(desktopIndependentWindow: source)
    let config = SCStreamConfiguration()
    config.ignoreShadowsSingleWindow = true
    config.showsCursor = false
    config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
    config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
    let frame = try await SCScreenshotManager.captureImage(
      contentFilter: filter, configuration: config)
    let png = try #require(
      NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("text-window.png"))
  }

  private func save(_ view: NSView, as name: String, in folder: String) throws {
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
  }

  private func differenceStrip(in view: NSView) -> DifferenceStripView? {
    if let strip = view as? DifferenceStripView { return strip }
    return view.subviews.lazy.compactMap { differenceStrip(in: $0) }.first
  }

  private func glyphScroll(in view: NSView) -> GlyphScrollView? {
    if let scroll = view as? GlyphScrollView { return scroll }
    return view.subviews.lazy.compactMap { glyphScroll(in: $0) }.first
  }
}
