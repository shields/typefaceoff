import CoreText
import Foundation
import Testing

@testable import TypefaceCore

@Suite struct RenderingTests {
  @Test func emphasisUsesTheSelectedFamilyAndPreservesItsSettings() throws {
    var config = FontConfiguration("HelveticaNeue-Bold")
    config.size = 31
    config.tracking = 0.025
    config.features["aat.1.2"] = 3
    let italic = try #require(FontRenderer.italicConfiguration(config))
    #expect(italic.postScriptName == "HelveticaNeue-BoldItalic")
    #expect(italic.size == config.size)
    #expect(italic.tracking == config.tracking)
    #expect(italic.features == config.features)
    #expect(FontRenderer.italicConfiguration(italic) == italic)
    let skia = try #require(FontCatalog().preferredFace(in: "Skia"))
    #expect(FontRenderer.italicConfiguration(.init(skia.id)) == nil)
    #expect(FontRenderer.italicConfiguration(.init("TypefaceOff-Does-Not-Exist")) == nil)
  }

  @Test func typographyGroupsIncludeReadOnlyAutomaticShaping() throws {
    let arial = FontConfiguration("ArialMT")
    let automatic = arial.face.features.filter(\.isAutomatic)
    #expect(!automatic.isEmpty)
    #expect(automatic.allSatisfy { $0.group == .automatic && $0.options.isEmpty })
    let required = try #require(automatic.first)
    var comparison = Comparison()
    let original = comparison
    comparison.setFeature(required, value: 0, side: .b)
    #expect(comparison == original)
    let helvetica = FontConfiguration("HelveticaNeue")
    #expect(helvetica.face.features.first { $0.id == "aat.6" }?.group == .numbers)
    #expect(helvetica.face.features.first { $0.id == "aat.17" }?.group == .characterVariants)
    #expect(arial.face.features.first { $0.id == "ot.liga" }?.group == .common)
  }

  @Test func xHeightDoesNotMeasureFallbackGlyphs() throws {
    let syriac = FontConfiguration("NotoSansSyriac-Regular")
    #expect(FontRenderer.isAvailable(syriac))
    #expect(!FontRenderer.supports("x", config: syriac))
    #expect(FontRenderer.xHeight(config: syriac) == nil)
    #expect(FontRenderer.xHeight(config: syriac, size: 100) == nil)
    #expect(FontRenderer.xHeight(config: .init("TypefaceOff-Does-Not-Exist")) == nil)
    let latin = FontConfiguration("HelveticaNeue")
    let height = try #require(FontRenderer.xHeight(config: latin))
    #expect(abs(height - 517) < 0.001)
    let points = try #require(FontRenderer.xHeight(config: latin, size: 22))
    #expect(abs(points - 11.374) < 0.001)
  }

  @Test func fractionalSkiaWidthChangesRenderedGlyphs() throws {
    let catalog = FontCatalog()
    let face = try #require(catalog.preferredFace(in: "Skia"))
    var config = FontConfiguration(face.id)
    #expect(FontRenderer.isAvailable(config))
    let axis = try #require(config.face.axes.first { $0.tag == "wdth" })
    #expect(axis.maximum - axis.minimum < 1)
    config.set(.axis(axis.id), to: 0.75, catalog: catalog)
    let narrow = FontRenderer.nativeMetrics("m", config: config).advance
    config.set(.axis(axis.id), to: 1.25, catalog: catalog)
    #expect(config.axes[axis.id] == 1.25)
    #expect(FontRenderer.nativeMetrics("m", config: config).advance > narrow)
  }

  @Test func trackingUsesPointsAndExplicitLigaturesSurviveTracking() {
    var config = FontConfiguration("HelveticaNeue")
    config.tracking = 0.1
    config.features["aat.1.2"] = 2
    let attributes = FontRenderer.attributes(config, size: 40)
    #expect(attributes[NSAttributedString.Key(kCTTrackingAttributeName as String)] as? Double == 4)
    #expect(attributes[NSAttributedString.Key(kCTLigatureAttributeName as String)] as? Int == 1)
    let enabled = FontRenderer.line("fi", config: config, size: 40, tracking: true)
    config.features["aat.1.2"] = 3
    let disabled = FontRenderer.line("fi", config: config, size: 40, tracking: true)
    #expect(CTLineGetGlyphCount(enabled) < CTLineGetGlyphCount(disabled))
  }

  @Test func nativeMetricsMatchFontTablesAndIgnoreSpecimenScaling() {
    var a = FontConfiguration("HelveticaNeue")
    let b = FontConfiguration("ArialMT")
    #expect(a.face.unitsPerEm == 1000)
    #expect(b.face.unitsPerEm == 2048)
    let metric = FontRenderer.nativeMetrics("a", config: a)
    #expect(abs(metric.advance - 537) < 0.01)
    #expect(abs(FontRenderer.nativeMetrics("a", config: b).advance - 1139) < 0.01)
    a.size = 77
    a.tracking = 0.1
    #expect(FontRenderer.nativeMetrics("a", config: a).advance == metric.advance)
  }

  @Test func missingGlyphsAndMissingFontsAreNotSilentlyCompared() {
    #expect(FontRenderer.supports("a", config: .init("ArialMT")))
    #expect(!FontRenderer.supports("🦄", config: .init("ArialMT")))
    #expect(!FontRenderer.isAvailable(.init("TypefaceOff-Does-Not-Exist")))
    #expect(!FontRenderer.supports("a", config: .init("TypefaceOff-Does-Not-Exist")))
  }

  @Test func identicalFontsScoreZeroAndTrackingOnlyChangesSpacing() {
    let a = FontConfiguration("HelveticaNeue")
    var b = a
    let same = Differences.compare("@", a: a, b: b)
    #expect(same.shape == 0)
    #expect(same.spacing == 0)
    b.tracking = 0.1
    let changed = Differences.compare("@", a: a, b: b)
    #expect(changed.shape == 0)
    #expect(abs(changed.spacing - 0.1 / 3) < 1e-9)
  }

  @Test func shapeIsSymmetricAndUniformScalingIsInvariant() {
    var a = FontConfiguration("HelveticaNeue")
    var b = FontConfiguration("ArialMT")
    let score = Differences.compare("@", a: a, b: b)
    #expect(score.shape > 0.1)
    #expect(abs(score.shape - Differences.compare("@", a: b, b: a).shape) < 0.001)
    a.size *= 2
    b.size *= 2
    #expect(score == Differences.compare("@", a: a, b: b))
  }

  @Test(.enabled(if: FontCatalog().preferredFace(in: "Inter Variable") != nil))
  func openTypeVariantsAffectShaping() async throws {
    let catalog = FontCatalog()
    let face = try #require(catalog.preferredFace(in: "Inter Variable"))
    let variant = try #require(face.features.first { $0.id == "ot.cv11" })
    #expect(variant.group == .characterVariants)
    #expect(face.features.contains { $0.group == .stylisticSets })
    #expect(variant.name != "Character variant 11")
    #expect(variant.name.localizedCaseInsensitiveContains("a"))
    let a = FontConfiguration(face.id)
    var b = a
    b.features["ot.cv11"] = 1
    b.axes[tagNumber("wght")] = 450
    #expect(FontRenderer.isAvailable(b))
    #expect(FontRenderer.supports("a", config: b))
    #expect(Differences.compare("a", a: a, b: b).shape > 0.1)
    let scores = try await DifferenceEngine().scores(a: a, b: b, sample: "")
    #expect(scores.count == 94)
    #expect(scores.first { $0.glyph == "a" }?.shape ?? 0 > 0.1)
  }

  @Test func unicodeNamesPreserveEveryScalarInAGrapheme() {
    let value = unicodeDescription("e\u{301}")
    #expect(value.contains("U+0065 LATIN SMALL LETTER E"))
    #expect(value.contains("U+0301 COMBINING ACUTE ACCENT"))
    #expect(Differences.candidates(sample: "e\u{301} 🐇").contains("e\u{301}"))
    #expect(Differences.candidates(sample: "").contains("@"))
  }
}
