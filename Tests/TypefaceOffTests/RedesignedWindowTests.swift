import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct RedesignedWindowTests {
  @Test(arguments: [960.0, 1024, 1440])
  func typographyOpensTheInspectorAtEveryWidth(width: Double) async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model), width: width, height: 600)
    defer { host.window.close() }
    try await host.press(width < 1120 ? "Open typography inspector" : "Font B typography")
    try await host.settle()
    if let folder = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] {
      let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
      host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: folder).appendingPathComponent("typography-jump-\(Int(width)).png")
      )
    }
    try await host.settle(
      until: {
        host.subviews.compactMap { $0 as? NSScrollView }.contains {
          $0.accessibilityIdentifier() == "Comparison inspector scroll area"
            && $0.contentView.bounds.minY > 100
        }
      }, describing: "Typography opens the inspector and scrolls to its section")
  }

  @Test(arguments: [960.0, 1440.0])
  func headerAndUnifiedInspectorShareSettings(width: Double) async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model), width: width, height: 900)
    defer { host.window.close() }
    try await host.settle()
    if let folder = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] {
      let view = host.window.contentView!.superview!
      let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: folder).appendingPathComponent("window-before-\(Int(width)).png"))
    }
    #expect(host.subviews.compactMap { $0 as? SpecificationFieldView }.count == 6)
    #expect(host.subviews.compactMap { $0 as? SpecificationSliderView }.isEmpty)
    try await host.press("Show Inspector")
    try await host.settle()
    #expect(host.subviews.compactMap { $0 as? SpecificationSliderView }.count == 6)
    #expect(host.window.contentLayoutRect.width >= 1280)
    let size = try #require(
      host.subviews.compactMap { $0 as? SpecificationFieldView }.first {
        $0.field.accessibilityIdentifier() == "Font A Size field"
      })
    try await host.submit("26", to: size.field)
    try await host.settle()
    #expect(model.comparison.a.size == 26 && model.comparison.b?.size == 26)
    let inspectorSize = try #require(
      host.subviews.compactMap { $0 as? SpecificationFieldView }.first {
        $0.field.accessibilityIdentifier() == "Font A Inspector Size field"
      })
    #expect(inspectorSize.field.stringValue == "26")
    let strip = try #require(host.subviews.compactMap { $0 as? DifferenceStripView }.first)
    let openWidth = strip.frame.width
    try await host.press("Show Inspector")
    try await host.settle { strip.frame.width > openWidth + 200 }
    if let folder = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] {
      let view = host.window.contentView!.superview!
      let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: folder).appendingPathComponent("window-\(Int(width)).png"))
    }
  }

  @Test func toolbarSearchChoosesCharactersAndFiltersLanguages() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    let field = try #require(
      host.subviews.compactMap { $0 as? NSSearchField }.first {
        $0.placeholderString == "Find Character"
      })
    try await host.submit("U+0042", to: field)
    try await host.settle {
      model.comparison.selectedGlyph == "B" && model.comparison.mode == .glyph
    }
    let modes = try #require(host.subviews.compactMap { $0 as? NSSegmentedControl }.first)
    modes.selectedSegment = 2
    modes.sendAction(modes.action!, to: modes.target)
    try await host.settle()
    #expect(model.comparison.mode == .languages)
    let languages = try #require(
      host.subviews.compactMap { $0 as? NSSearchField }.first {
        $0.placeholderString == "Search Languages"
      })
    try await host.submit("English", to: languages)
    #expect(model.languages.filter.query == "English")
  }
}
