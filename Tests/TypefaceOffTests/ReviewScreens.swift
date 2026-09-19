import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct ReviewScreens {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["TYPEFACEOFF_REVIEW_DIR"] != nil))
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
      ("single-text", 1280, Comparison(b: nil)),
    ]
    var missing = Comparison()
    missing.sample = .custom
    missing.customText = "Missing characters stay identifiable: 🦄 🦄 👩‍🚀."
    cases.append(("missing-characters", 1280, missing))
    missing.b = .init("TypefaceOff-Does-Not-Exist")
    cases.append(("missing-font", 1280, missing))
    for sample in [Sample.poetry, .alphabet, .numerals] {
      var comparison = Comparison()
      comparison.sample = sample
      cases.append((sample.rawValue, 1440, comparison))
    }
    var attribution = Comparison()
    attribution.a.size = 14
    attribution.b?.size = 14
    cases.append(("attribution", 1440, attribution))
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
      let document = WorkbenchDocument(comparison: comparison)
      try comparison.encoded().write(
        to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).typefaceoff"))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let host = NSHostingView(
        rootView: WorkbenchView(document: document).preferredColorScheme(.dark))
      host.sizingOptions = []
      window.contentView = host
      window.setContentSize(NSSize(width: width, height: height))
      window.makeKeyAndOrderFront(nil)
      try await Task.sleep(for: .milliseconds(name == "variable" ? 2000 : 750))
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let data = try #require(bitmap.representation(using: .png, properties: [:]))
      try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
      #expect(abs(host.bounds.width - width) < 0.5)
      #expect(abs(host.bounds.height - height) < 0.5)
      window.close()
    }
    let match = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 530, height: 410), styleMask: [.titled],
      backing: .buffered, defer: false)
    match.isReleasedWhenClosed = false
    let host = NSHostingView(
      rootView: MatchSheet(document: WorkbenchDocument()).preferredColorScheme(.dark))
    match.contentView = host
    match.orderFront(nil)
    try await Task.sleep(for: .milliseconds(200))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("match.png"))
    match.close()
  }
}
