// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct DifferenceIndexTests {
  @Test func removingAndRestoringFontBKeepsExistingCellsSafe() async throws {
    let model = WorkbenchModel()
    let ranking = RankingModel()
    ranking.scores = [GlyphDifference(glyph: "A", shape: 0.5, spacing: 0)]
    let host = WorkbenchTestHost(
      DifferenceIndex(
        model: model, ranking: ranking, inspectorOpen: false, select: { _ in }, navigate: { _ in }),
      width: 960, height: 76)
    defer { host.window.close() }
    try await host.settle()
    for b: FontConfiguration? in [nil, .init("ArialMT"), nil] {
      model.comparison.b = b
      try await host.settle()
      #expect(host.subviews.compactMap { $0 as? DifferenceStripView }.count == (b == nil ? 0 : 1))
    }
  }

  @Test(arguments: [(960.0, 12, 12), (1120.0, 16, 15), (1440.0, 22, 22)])
  func cellsFitTheGridAndExposeTheirRank(layout: (Double, Int, Int)) async throws {
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
    let expected =
      NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor ? layout.2 : layout.1
    #expect(Int(strip.contentSize.width / 48) == expected)
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
