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

import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import TypefaceCore

@Suite struct RegionCoverageTests {
  @Test func cancelledFamilyScoringRemainsCancellationRatherThanUnavailability() async {
    await #expect(throws: CancellationError.self) {
      try await FontSimilarityEngine.familyScore(family: "Arial") { throw CancellationError() }
    }
  }
  @Test func selectingBStylePropagatesTheLockedWeightAndItalicTraitToA() {
    let catalog = FontCatalog()
    let original = FontConfiguration("HelveticaNeue")
    var comparison = Comparison(a: original, b: original)
    let boldItalic = FontFace.named("HelveticaNeue-BoldItalic")
    comparison.selectFace(boldItalic, side: .b, catalog: catalog)
    #expect(comparison.a.postScriptName == boldItalic.id)
    #expect(comparison.b?.postScriptName == boldItalic.id)
    #expect(comparison.a.size == original.size && comparison.b?.size == original.size)
  }

  @Test(arguments: [false, true])
  func resettingAnAbsentBLeavesAUnchanged(locked: Bool) {
    var comparison = Comparison(b: nil)
    comparison.appearanceLocked = locked
    let original = comparison
    comparison.resetAppearance(side: .b, catalog: FontCatalog())
    #expect(comparison == original)
  }

  @Test func spacingHighlightsExcludePureShapeDifferencesAndDisabledMetrics() {
    let scores = [
      GlyphDifference(glyph: "a", shape: 0, spacing: 1),
      GlyphDifference(glyph: "b", shape: 1, spacing: 0),
    ]
    #expect(
      Differences.highlights(scores, text: "ab", shape: false, spacing: true, frequency: false)
        == ["a"])
    #expect(
      Differences.highlights(scores, text: "ab", shape: false, spacing: false, frequency: false)
        .isEmpty)
  }

  @Test func missingRunFontMetadataDoesNotPassGlyphSupportChecks() {
    let config = FontConfiguration("ArialMT")
    let line = FontRenderer.line("a", config: config, size: 22)
    #expect(
      !FontRenderer.supports(
        line, configuredName: config.postScriptName,
        runAttributes: { _ in
          [:]
        }))
  }

  @Test func nullInkBoundsKeepTheTypographicAdvance() {
    let line = FontRenderer.line("a", config: .init("ArialMT"), size: 22)
    let measurement = FontRenderer.measure(line, inkBounds: { _ in .null })
    #expect(measurement.bounds == .zero)
    #expect(measurement.advance == CTLineGetTypographicBounds(line, nil, nil, nil))
    #expect(measurement.advance > 0)
  }

  @Test func aZeroWidthMaskHasNoPixels() {
    #expect(
      FontRenderer.mask(
        "a", config: .init("ArialMT"), size: 22, width: 0, height: 1,
        origin: .zero
      ).isEmpty)
  }

  @Test func aFailedBitmapAllocationSurfacesAsARenderingError() {
    let line = FontRenderer.line("a", config: .init("ArialMT"), size: 22)
    #expect(throws: SimilarityError.renderingFailed) {
      try SimilarityImage.rasterize(line, scale: 2, radius: 4, makeContext: { _, _, _ in nil })
    }
  }
}
