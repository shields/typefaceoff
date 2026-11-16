import Foundation
import Testing

@testable import TypefaceCore

@Suite struct SpecificationAppearanceTests {
  let catalog = FontCatalog()
  let locale = Locale(identifier: "en_US")

  @Test func sectionResetClearsCalibrationEvenWhenBothFacesAreAtTheirDefaults() {
    var comparison = Comparison(a: .init("Arial-BoldMT"), b: .init("ArialMT"))
    comparison.selectFace(FontFace(postScriptName: "ArialMT"), side: .a, catalog: catalog)
    #expect(comparison.a == FontConfiguration("ArialMT"))
    #expect(comparison.b == FontConfiguration("ArialMT"))
    #expect(comparison.link?.weightOffset == -300)
    #expect(comparison.hasAppearanceChanges(catalog: catalog))
    comparison.resetAppearance(catalog: catalog)
    #expect(comparison.link?.weightOffset == 0)
    #expect(!comparison.hasAppearanceChanges(catalog: catalog))
  }

  @Test func sectionResetIncludesStaticStyleAndPreservesUnavailableFonts() {
    var comparison = Comparison()
    #expect(!comparison.hasAppearanceChanges(catalog: catalog))
    comparison.a = .init("HelveticaNeue-Bold")
    comparison.a.features["ot.kern"] = 0
    comparison.b?.size = 35
    #expect(comparison.hasAppearanceChanges(catalog: catalog))
    comparison.resetAppearance(catalog: catalog)
    #expect(comparison.a.postScriptName == "HelveticaNeue" && comparison.b?.size == 22)
    #expect(comparison.a.features["ot.kern"] == 0 && comparison.appearanceLocked)
    comparison.appearanceLocked = false
    comparison.b = .init("TypefaceOff-Not-Installed")
    comparison.b?.size = 40
    let missing = comparison.b
    comparison.resetAppearance(catalog: catalog)
    #expect(comparison.b == missing && !comparison.appearanceLocked)
    comparison.b = nil
    comparison.resetAppearance(catalog: catalog)
    #expect(!comparison.hasAppearanceChanges(catalog: catalog))
  }

  @Test func opticalSizeDefaultsFollowPointSizeWithinTheFontsRange() {
    let optical = FontAxis(
      id: tagNumber("opsz"), name: "Optical size", minimum: 8, maximum: 72, defaultValue: 12)
    let width = FontAxis(
      id: tagNumber("wdth"), name: "Width", minimum: 50, maximum: 200, defaultValue: 100)
    for (size, expected) in [(4.0, 8.0), (22, 22), (44, 44), (144, 72)] {
      #expect(SpecificationSetting.defaultAxisValue(optical, size: size) == expected)
      #expect(SpecificationSetting.defaultAxisValue(width, size: size) == 100)
    }
  }

  @Test func axesAreUnitedByTagAndSlidersRespectNativeRanges() {
    let weight = FontAxis(
      id: tagNumber("wght"), name: "Weight", minimum: 1, maximum: 2, defaultValue: 1)
    let width = FontAxis(
      id: tagNumber("wdth"), name: "Width", minimum: 1, maximum: 1, defaultValue: 1)
    #expect(
      SpecificationSetting.settings(a: [weight], b: [width, weight]) == [
        .size, .leading, .tracking, .axis(weight.id), .axis(width.id),
      ])
    for (setting, range) in [
      (SpecificationSetting.size, 10.0...144), (.leading, 1...288), (.tracking, -0.12...0.15),
      (.axis(weight.id), 1...2),
    ] {
      #expect(setting.position(range.lowerBound, in: range) == 0)
      #expect(setting.position(range.upperBound, in: range) == 1)
      #expect(setting.value(at: -1, in: range) == range.lowerBound)
      #expect(setting.value(at: 2, in: range) == range.upperBound)
      let value = setting.value(at: 0.37, in: range)
      #expect(abs(setting.position(value, in: range) - 0.37) < 0.000_001)
    }
    #expect(SpecificationSetting.size.value(at: 0.5, in: 10...144) < 40)
    #expect(SpecificationSetting.axis(width.id).position(1, in: 1...1) == 0)
  }

  @Test func resetUsesEachFontsDefaultsAndKeepsUnrelatedCalibration() throws {
    let name = try #require(catalog.preferredFace(in: "Skia")).id
    var comparison = Comparison(a: .init(name), b: .init(name))
    comparison.b?.size = 44
    comparison.b?.tracking = 0.01
    comparison.calibrate()
    for setting in SpecificationSetting.settings(a: comparison.a.face.axes, b: []) {
      #expect(!setting.isChanged(in: comparison.a))
      let rules = try #require(setting.rules(for: comparison.a))
      setting.apply(
        .number(rules.range.upperBound), to: &comparison, side: .a, both: false, catalog: catalog)
      #expect(setting.isChanged(in: comparison.a))
      let tracking = comparison.link?.trackingOffset
      setting.reset(in: &comparison, catalog: catalog)
      #expect(!setting.isChanged(in: comparison.a) && !setting.isChanged(in: comparison.b!))
      #expect(comparison.appearanceLocked)
      if setting != .tracking { #expect(comparison.link?.trackingOffset == tracking) }
    }
    comparison.b = nil
    comparison.a.size = 30
    SpecificationSetting.size.reset(in: &comparison, catalog: catalog)
    #expect(comparison.a.size == 22)
    comparison.b = .init("TypefaceOff-Not-Installed")
    let missing = comparison.b
    SpecificationSetting.size.reset(in: &comparison, catalog: catalog)
    #expect(comparison.b == missing)
    comparison.b = .init("HelveticaNeue")
    SpecificationSetting.axis(tagNumber("wdth")).reset(in: &comparison, catalog: catalog)
    #expect(comparison.b?.postScriptName == "HelveticaNeue")
  }

  @Test func relationsUseStoredCalibrationAndNativeAxisPrecision() throws {
    var comparison = Comparison()
    #expect(SpecificationSetting.size.relation(in: comparison, locale: locale) == nil)
    #expect(SpecificationSetting.tracking.relation(in: comparison, locale: locale) == nil)
    #expect(
      SpecificationSetting.axis(tagNumber("wdth")).relation(in: comparison, locale: locale) == nil)
    comparison.b?.size = 21.5
    comparison.b?.tracking = 0.004
    comparison.a.leading = 28
    comparison.b?.leading = 27
    comparison.calibrate()
    #expect(SpecificationSetting.size.relation(in: comparison, locale: locale) == "×0.977")
    #expect(SpecificationSetting.tracking.relation(in: comparison, locale: locale) == "+0.004 em")
    #expect(SpecificationSetting.leading.relation(in: comparison, locale: locale) == "−1.000 pt")
    comparison.link?.axisOffsets[tagNumber("wght")] = 40
    #expect(
      SpecificationSetting.axis(tagNumber("wght")).relation(in: comparison, locale: locale) == "+40"
    )
    comparison.link?.axisOffsets[tagNumber("wdth")] = 0.25
    #expect(
      SpecificationSetting.axis(tagNumber("wdth")).relation(in: comparison, locale: locale)
        == "+0.25")
    comparison.appearanceLocked = false
    #expect(SpecificationSetting.size.relation(in: comparison, locale: locale) == nil)
    comparison.appearanceLocked = true
    comparison.link = nil
    #expect(SpecificationSetting.size.relation(in: comparison, locale: locale) == nil)
    comparison.b = nil
    #expect(SpecificationSetting.size.relation(in: comparison, locale: locale) == nil)
    comparison.b = .init("TypefaceOff-Not-Installed")
    #expect(SpecificationSetting.size.relation(in: comparison, locale: locale) == nil)
    comparison.a = .init("TypefaceOff-Not-Installed")
    #expect(SpecificationSetting.size.relation(in: comparison, locale: locale) == nil)
  }
}
