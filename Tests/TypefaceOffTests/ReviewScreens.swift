import AppKit
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
    _ = NSApplication.shared
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
      ("text-1280", 1280, Comparison()), ("glyph-1440", 1440, glyph),
      ("glyph-zoom", 1280, glyph), ("single-zoom", 1280, single),
      ("single-text", 1280, Comparison(b: nil)),
    ]
    var both = glyph
    both.spacing = true
    cases.append(("both-differences", 1280, both))
    var neither = glyph
    neither.shape = false
    cases.append(("no-highlights", 1280, neither))
    var frequencyOn = glyph
    frequencyOn.spacing = true
    cases.append(("frequency-on", 1280, frequencyOn))
    var frequencyOff = frequencyOn
    frequencyOff.frequency = false
    cases.append(("frequency-off", 1280, frequencyOff))
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
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let host = NSHostingView(
        rootView: WorkbenchView(model: model).preferredColorScheme(.dark))
      host.sizingOptions = []
      window.contentView = host
      window.setContentSize(NSSize(width: width, height: height))
      window.makeKeyAndOrderFront(nil)
      try await Task.sleep(for: .milliseconds(name == "variable" ? 2000 : 750))
      host.layoutSubtreeIfNeeded()
      if name.hasSuffix("-zoom"), let scroll = glyphScroll(in: host) {
        scroll.setZoom(2)
        scroll.zoomChanged(2)
        try await Task.sleep(for: .milliseconds(100))
      }
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let data = try #require(bitmap.representation(using: .png, properties: [:]))
      try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
      #expect(abs(host.bounds.width - width) < 0.5)
      #expect(abs(host.bounds.height - height) < 0.5)
      window.close()
    }
    let match = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 660), styleMask: [.titled],
      backing: .buffered, defer: false)
    match.isReleasedWhenClosed = false
    var matching = Comparison()
    matching.sample = .custom
    matching.customText = "Hamburg minimum AV To fi fl 1820"
    let fit = FontFitModel()
    let host = NSHostingView(
      rootView: MatchSheet(model: WorkbenchModel(comparison: matching), fit: fit)
        .preferredColorScheme(.dark))
    match.contentView = host
    match.orderFront(nil)
    try await Task.sleep(for: .seconds(5))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("match.png"))
    match.close()
    fit.stop()
    let ranking = FamilySimilarityModel()
    ranking.sort = .similarity
    let picker = WorkbenchTestHost(
      FontFamilyPicker(
        families: catalog.families, currentFamily: "Arial",
        allowsNone: true, ranking: ranking, reference: .init("HelveticaNeue"), catalog: catalog,
        choose: { _ in }), width: 300, height: 400)
    try await Task.sleep(for: .seconds(6))
    let pickerBitmap = try #require(
      picker.view.bitmapImageRepForCachingDisplay(in: picker.view.bounds))
    picker.view.cacheDisplay(in: picker.view.bounds, to: pickerBitmap)
    let pickerData = try #require(pickerBitmap.representation(using: .png, properties: [:]))
    try pickerData.write(
      to: URL(fileURLWithPath: folder).appendingPathComponent("similarity-picker.png"))
    picker.window.close()
    let search = WorkbenchTestHost(
      CharacterSearchPicker(comparison: Comparison()) { _ in }, width: 440, height: 460)
    try await Task.sleep(for: .seconds(1))
    search.enter(
      "arrow", in: try #require(search.subviews.compactMap { $0 as? NSSearchField }.first))
    try await Task.sleep(for: .seconds(4))
    let searchBitmap = try #require(
      search.view.bitmapImageRepForCachingDisplay(in: search.view.bounds))
    search.view.cacheDisplay(in: search.view.bounds, to: searchBitmap)
    let searchData = try #require(searchBitmap.representation(using: .png, properties: [:]))
    try searchData.write(
      to: URL(fileURLWithPath: folder).appendingPathComponent("character-search.png"))
    search.window.close()

  }

  private func glyphScroll(in view: NSView) -> GlyphScrollView? {
    if let scroll = view as? GlyphScrollView { return scroll }
    return view.subviews.lazy.compactMap { glyphScroll(in: $0) }.first
  }
}
