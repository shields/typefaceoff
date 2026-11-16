import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct DifferenceIndexTests {
  @Test(arguments: [(960.0, 12), (1120.0, 16), (1440.0, 22)])
  func cellsFitTheGridAndExposeTheirRank(layout: (Double, Int)) async throws {
    let model = WorkbenchModel()
    let ranking = RankingModel()
    ranking.scores = (33...90).map {
      GlyphDifference(glyph: String(UnicodeScalar($0)!), shape: Double($0) / 100, spacing: 0)
    }
    var selected: String?
    let host = WorkbenchTestHost(
      DifferenceIndex(
        model: model, ranking: ranking, inspectorOpen: false, select: { selected = $0 },
        navigate: { _ in }), width: layout.0, height: 76)
    defer { host.window.close() }
    try await host.settle()
    let strip = try #require(host.subviews.compactMap { $0 as? DifferenceStripView }.first)
    #expect(Int(strip.contentSize.width / 48) == layout.1)
    let first = Differences.ranked(ranking.scores, shape: true, spacing: false, frequency: true)[0]
    let label = "Inspect \(unicodeDescription(first.glyph))"
    let element = try #require(try await host.element(label) as? NSObject)
    let value = element.perform(NSSelectorFromString("accessibilityValue"))?.takeUnretainedValue()
    #expect(value as? String == "1 of 58")
    try await host.press(label)
    #expect(selected == first.glyph)
    model.updatePresentation {
      $0.mode = .glyph
      $0.selectedGlyph = first.glyph
    }
    try await host.settle()
    #expect(strip.contentView.bounds.minX == 0)
    try await host.press("Shape")
    try await host.press("Spacing")
    try await host.press("Frequency")
    #expect(!model.comparison.shape && model.comparison.spacing && !model.comparison.frequency)
    try await host.settle()
    try await host.press("Frequency")
    #expect(model.comparison.frequency)
  }

  @Test func emptyMissingAndComputingStatesExplainWhyThereAreNoCells() async throws {
    let model = WorkbenchModel()
    let ranking = RankingModel()
    let host = WorkbenchTestHost(
      DifferenceIndex(
        model: model, ranking: ranking, inspectorOpen: false, select: { _ in }, navigate: { _ in }),
      width: 960, height: 76)
    defer { host.window.close() }
    try await host.settle()
    #expect(host.subviews.compactMap { $0 as? DifferenceStripView }.isEmpty)
    ranking.comparing = true
    try await host.settle()
    _ = try await host.element("Comparing glyphs")
    #expect(host.subviews.compactMap { $0 as? DifferenceStripView }.count == 1)
    ranking.comparing = false
    for comparison in [
      Comparison(b: nil), Comparison(b: .init("TypefaceOff-Missing")),
      Comparison(a: .init("TypefaceOff-Missing")),
    ] {
      model.comparison = comparison
      try await host.settle()
      #expect(host.subviews.compactMap { $0 as? DifferenceStripView }.isEmpty)
      #expect(!host.elements.contains { $0.accessibilityLabel?() == "Shape" })
    }
  }
}
