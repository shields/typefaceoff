import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct GlyphStageTests {
  @Test(arguments: [960.0, 1120, 1440])
  func onlyTheOverlayZoomsAndGlyphNavigationKeepsTheBaseline(width: Double) async throws {
    var comparison = Comparison()
    comparison.mode = .glyph
    comparison.selectedGlyph = "@"
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(WorkbenchView(model: model), width: width, height: 900)
    defer { host.window.close() }
    try await host.settle()
    let scroll = try #require(host.subviews.compactMap { $0 as? GlyphScrollView }.first)
    let solos = try #require(host.subviews.compactMap { $0 as? GlyphSoloView }.first)
    #expect(abs(scroll.frame.width - (width - 64) / 2) < 1)
    #expect(
      scroll.canvas.figures.allSatisfy {
        $0.origin.x >= 0 && $0.origin.x + $0.advance <= scroll.frame.width
      })
    let baseline = scroll.canvas.layout.baseline
    let soloFrame = solos.convert(solos.bounds, to: host.view)
    let soloInk = try bitmap(solos)
    if width == 1440 {
      let values = Set(
        host.elements.compactMap { element -> String? in
          guard element.accessibilityRole?() == .staticText else { return nil }
          let value: String? = element.accessibilityValue?()
          return value
        })
      #expect(values.contains("0.800 em") && values.contains("1.015 em"))
    }
    try await capture(host, name: "glyph-\(Int(width))")
    try await host.press("Zoom in")
    try await host.settle()
    #expect(scroll.magnification == 1.25)
    #expect(solos.convert(solos.bounds, to: host.view) == soloFrame)
    #expect(try bitmap(solos) == soloInk)
    for glyph in [".", "Å", "j", "e\u{301}", "🦄", " "] {
      model.updatePresentation { $0.selectedGlyph = glyph }
      try await host.settle()
      #expect(scroll.canvas.layout.baseline == baseline)
      #expect(scroll.magnification == 1.25)
      #expect(solos.convert(solos.bounds, to: host.view) == soloFrame)
    }
    try await host.press("Reset glyph zoom")
    try await host.settle()
    #expect(scroll.magnification == 1 && scroll.contentView.bounds.origin == .zero)
  }

  @Test func missingGlyphsRetainTheAvailableInkAndMissingFontsStayVisible() async throws {
    var comparison = Comparison()
    comparison.mode = .glyph
    comparison.selectedGlyph = "Ƙ"
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(WorkbenchView(model: model), width: 1440, height: 900)
    defer { host.window.close() }
    try await host.settle()
    let scroll = try #require(host.subviews.compactMap { $0 as? GlyphScrollView }.first)
    #expect(scroll.canvas.figures[0].line == nil)
    #expect(scroll.canvas.figures[1].line != nil)
    let image = try #require(
      scroll.canvas.bitmapImageRepForCachingDisplay(in: scroll.canvas.bounds))
    scroll.canvas.cacheDisplay(in: scroll.canvas.bounds, to: image)
    #expect(hasBlueInk(image))
    try await capture(host, name: "glyph-missing")
    model.updatePresentation { $0.swap() }
    try await host.settle()
    #expect(scroll.canvas.figures[0].line != nil && scroll.canvas.figures[1].line == nil)
    model.updatePresentation {
      $0.swap()
      $0.selectedGlyph = "@"
      $0.shape = false
      $0.spacing = true
    }
    try await host.settle()
    #expect(scroll.canvas.figures[0].origin.x == scroll.canvas.figures[1].origin.x)
    try await capture(host, name: "glyph-spacing")
    model.updatePresentation {
      $0.b = nil
      $0.selectedGlyph = "@"
    }
    try await host.settle()
    try await capture(host, name: "glyph-single")
    #expect(scroll.canvas.figures[0].line != nil && scroll.canvas.figures[1].line == nil)
    model.updatePresentation { $0.b = .init("TypefaceOff-Does-Not-Exist") }
    try await host.settle()
    try await capture(host, name: "glyph-missing-font")
    #expect(!scroll.canvas.figures[1].installed && scroll.canvas.figures[1].line == nil)
  }

  @Test func detachedGuidesPassThroughInputAndRejectAnArchiveWithoutItsCanvas() throws {
    let scroll = GlyphScrollView()
    scroll.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
    scroll.layoutSubtreeIfNeeded()
    scroll.canvas.update(Comparison())
    let guides = scroll.annotations
    #expect(guides.hitTest(CGPoint(x: 100, y: 100)) == nil)
    #expect(GlyphGuideView(coder: NSCoder()) == nil)
    guides.draw(.zero)
    #expect(!(try bitmap(guides)).isEmpty)
    let solo = GlyphSoloView()
    solo.draw(.zero)
  }

  private func bitmap(_ view: NSView) throws -> Data {
    let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: image)
    return Data(bytes: try #require(image.bitmapData), count: image.bytesPerRow * image.pixelsHigh)
  }

  private func hasBlueInk(_ image: NSBitmapImageRep) -> Bool {
    for y in stride(from: 0, to: image.pixelsHigh, by: 4) {
      for x in stride(from: 0, to: image.pixelsWide, by: 4) {
        if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          color.blueComponent > color.redComponent + 0.2 && color.redComponent < 0.4
        {
          return true
        }
      }
    }
    return false
  }

  private func capture<Content>(_ host: WorkbenchTestHost<Content>, name: String) async throws {
    guard let directory = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] else {
      return
    }
    let image = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: image)
    try #require(image.representation(using: .png, properties: [:])).write(
      to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
  }
}
