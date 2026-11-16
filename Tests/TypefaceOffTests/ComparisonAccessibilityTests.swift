import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct ComparisonAccessibilityTests {
  @Test func contrastPaletteAndMenusStayLight() throws {
    let original = NSApp.appearance
    defer { NSApp.appearance = original }
    for increased in [false, true, false] {
      WorkbenchStyle.useLightAppearance(increasedContrast: increased)
      let appearance = try #require(NSApp.appearance)
      #expect(appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
      let usesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
      #expect(WorkbenchStyle.increasedContrast(appearance) == usesContrast)
      appearance.performAsCurrentDrawingAppearance {
        let colors: [(NSColor, Int, Int)] = [
          (WorkbenchStyle.red, 0xb43b43, 0x8f2530),
          (WorkbenchStyle.blue, 0x286b9d, 0x1a527d),
          (NSColor(WorkbenchStyle.secondaryInk), 0x5a5e66, 0x3f4248),
          (NSColor(WorkbenchStyle.track), 0x8e939b, 0x5a5e66),
          (NSColor(WorkbenchStyle.hairline), 0xc9ccd2, 0x8e939b),
          (NSColor(WorkbenchStyle.fieldUnderline), 0x8e939b, 0x1b1c1f),
        ]
        for (color, normal, contrast) in colors {
          let resolved = color.usingColorSpace(.genericRGB)!
          let actual =
            Int((resolved.redComponent * 255).rounded()) << 16
            | Int((resolved.greenComponent * 255).rounded()) << 8
            | Int((resolved.blueComponent * 255).rounded())
          #expect(actual == (usesContrast ? contrast : normal))
        }
      }
    }
    TypefaceOffAppDelegate().updateAppearance()
    #expect(NSApp.appearance?.name != .darkAqua)
  }

  @Test func underlinesChangeWithoutReshapingOrSelectingMissingGlyphs() async throws {
    let specimen = SpecimenText(
      config: .init("HelveticaNeue"), text: "fi a 🦄", highlights: ["a", "🦄"])
    let host = WorkbenchTestHost(
      specimen.environment(\._accessibilityDifferentiateWithoutColor, false), width: 400,
      height: 250
    )
    defer { host.window.close() }
    try await host.settle()
    let view = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let storage = try #require(view.textStorage)
    let layout = try #require(view.layoutManager)
    let original = NSAttributedString(attributedString: storage)
    let a = try #require(view.spans.first { $0.glyph == "a" })
    let missing = try #require(view.spans.first { !$0.supported })
    view.setSelectedRange(a.range)
    for enabled in [true, false, true] {
      host.setContent(specimen.environment(\._accessibilityDifferentiateWithoutColor, enabled))
      try await host.settle()
      view.refreshHighlights()
      #expect(storage == original && view.selectedRange() == a.range)
      #expect(view.underlineHighlights == enabled)
      #expect(
        layout.temporaryAttribute(
          .underlineStyle, atCharacterIndex: a.range.location, effectiveRange: nil)
          as? Int == (enabled ? NSUnderlineStyle.single.rawValue : nil))
      #expect(
        layout.temporaryAttribute(
          .underlineStyle, atCharacterIndex: missing.range.location, effectiveRange: nil)
          == nil)
    }
  }

  @Test func rasterHatchesKeepSharedInkAndAlphaAndUseOppositeSlopes() throws {
    let size = 24
    let full = [UInt8](repeating: 255, count: size * size)
    let empty = [UInt8](repeating: 0, count: full.count)
    let red = try raster(full, empty, size: size)
    let blue = try raster(empty, full, size: size)
    let shared = try raster(full, full, size: size)
    let clear = try raster(empty, empty, size: size)
    let partial = (0..<full.count).map { UInt8($0 % 256) }
    let antialiased = try raster(partial, empty, size: size)
    for pixel in 0..<full.count {
      #expect(shared[pixel * 4] == 27 && shared[pixel * 4 + 3] == 255)
      #expect(clear[pixel * 4 + 3] == 0)
      #expect(antialiased[pixel * 4 + 3] == partial[pixel])
      #expect(red[pixel * 4 + 3] == 255 && blue[pixel * 4 + 3] == 255)
    }
    func bright(_ pixels: [UInt8], _ x: Int, _ y: Int) -> Bool {
      pixels[(y * size + x) * 4] > 200
    }
    #expect((0..<full.count).contains { red[$0 * 4] > 200 })
    #expect((0..<full.count).contains { red[$0 * 4] < 200 })
    for x in 2..<20 {
      for y in 2..<20 {
        #expect(bright(red, x, y) == bright(red, x + 1, y - 1))
        #expect(bright(blue, x, y) == bright(blue, x + 1, y + 1))
      }
    }
    #expect(
      GlyphOverlay.pixels([255, 0, 255], [0, 255, 255], increasedContrast: true)
        == [143, 37, 48, 255, 26, 82, 125, 255, 27, 28, 31, 255])
  }

  @Test(arguments: [960.0, 1440])
  func openWindowPropagatesDisplaySettingsAcrossModes(width: Double) async throws {
    let original = NSApp.appearance
    defer { NSApp.appearance = original }
    WorkbenchStyle.useLightAppearance(increasedContrast: true)
    let model = WorkbenchModel()
    model.updatePresentation {
      $0.mode = .glyph
      $0.selectedGlyph = "@"
    }
    let content = WorkbenchView(model: model)
      .environment(\._accessibilityDifferentiateWithoutColor, true)
      .environment(\._accessibilityReduceMotion, true)
      .environment(\._accessibilityReduceTransparency, true)
      .environment(\._colorSchemeContrast, .increased)
    let host = WorkbenchTestHost(content, width: width, height: 900)
    defer { host.window.close() }
    try await host.settle {
      !host.subviews.compactMap { $0 as? GlyphDifferenceDrawingView }.isEmpty
    }
    let canvas = try #require(host.subviews.compactMap { $0 as? GlyphDrawingView }.first)
    #expect(canvas.differentiateWithoutColor)
    let previews = host.subviews.compactMap { $0 as? GlyphDifferenceDrawingView }
    #expect(previews.allSatisfy { $0.differentiateWithoutColor })
    try capture(host, name: "accessibility-glyph-\(Int(width))")
    try await host.press("Zoom in")
    try await host.settle()
    try capture(host, name: "accessibility-zoom-\(Int(width))")
    model.updatePresentation { $0.mode = .text }
    try await host.settle()
    #expect(
      host.subviews.compactMap { $0 as? SpecimenNSTextView }.allSatisfy { $0.underlineHighlights })
    try capture(host, name: "accessibility-text-\(Int(width))")
    try await host.press(width < 1120 ? "Open typography inspector" : "Font A typography")
    try await host.settle()
    _ = try await host.element("Comparison inspector scroll area")
  }

  @Test func canvasDescribesOnlyInstalledFontsAndReportsMissingCharacters() throws {
    let font = FontConfiguration("HelveticaNeue")
    let missing = FontConfiguration("TypefaceOff-Not-Installed")
    let cases: [(FontConfiguration, FontConfiguration?, String, [String])] = [
      (font, .init("ArialMT"), "@", ["Font A in red, font B in blue, shared ink in black."]),
      (font, nil, "@", ["Font A."]),
      (font, missing, "@", ["Font A.", "Font B is not installed."]),
      (missing, font, "@", ["Font B.", "Font A is not installed."]),
      (
        missing, missing, "@",
        ["No installed fonts.", "Font A is not installed.", "Font B is not installed."]
      ),
      (font, .init("ArialMT"), "Ƙ", ["Character unavailable in Font A."]),
      (.init("ArialMT"), font, "Ƙ", ["Character unavailable in Font B."]),
      (font, nil, "🦄", ["Font A.", "Character unavailable in Font A."]),
    ]
    let canvas = GlyphDrawingView()
    for (a, b, glyph, expected) in cases {
      var comparison = Comparison(a: a, b: b)
      comparison.selectedGlyph = glyph
      canvas.update(comparison)
      let description = try #require(canvas.accessibilityLabel())
      #expect(description.hasPrefix(unicodeDescription(glyph)))
      for phrase in expected { #expect(description.contains(phrase)) }
      if !FontRenderer.isAvailable(a) || b == nil || b == missing {
        #expect(!description.contains("in red") && !description.contains("in blue"))
      }
    }
  }

  private func raster(_ a: [UInt8], _ b: [UInt8], size: Int) throws -> [UInt8] {
    let context = try #require(
      CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    GlyphOverlay.draw(
      a, b, width: size, height: size, context: context,
      rect: CGRect(x: 0, y: 0, width: size, height: size), differentiateWithoutColor: true)
    ComparisonHatch(rising: true).draw(in: context, rect: .zero)
    return Array(
      UnsafeBufferPointer(
        start: context.data!.assumingMemoryBound(to: UInt8.self), count: size * size * 4))
  }

  private func capture<Content>(_ host: WorkbenchTestHost<Content>, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] else {
      return
    }
    let image = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: image)
    try #require(image.representation(using: .png, properties: [:])).write(
      to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
  }
}
