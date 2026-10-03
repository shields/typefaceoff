import Foundation
import Testing

@testable import TypefaceCore

@Suite struct LeadingTests {
  @Test func explicitLeadingPreservesCalibrationInBothDirectionsAndAfterClamping() {
    var comparison = Comparison()
    comparison.a.leading = 24
    comparison.b?.leading = 28
    comparison.calibrate()
    comparison.setLeading(36, side: .a)
    #expect(comparison.a.leading == 36 && comparison.b?.leading == 40)
    comparison.setLeading(34, side: .b)
    #expect(comparison.a.leading == 30 && comparison.b?.leading == 34)
    comparison.setLeading(288, side: .a)
    #expect(comparison.a.leading == 288 && comparison.b?.leading == 288)
    comparison.setLeading(24, side: .a)
    #expect(comparison.b?.leading == 28)
    comparison.setLeading(1, side: .b)
    #expect(comparison.a.leading == 1 && comparison.b?.leading == 1)
    comparison.setLeading(28, side: .b)
    #expect(comparison.a.leading == 24)
    comparison.swap()
    #expect(comparison.link?.leadingOffset == -4)
    comparison.setLeading(36, side: .a)
    #expect(comparison.b?.leading == 32)
  }

  @Test(arguments: [Side.a, .b])
  func automaticLeadingResetsBothLinkedSidesWithoutRecalibratingOtherSettings(side: Side) {
    var comparison = Comparison()
    comparison.a.leading = 24
    comparison.b?.leading = 30
    comparison.b?.size = 44
    comparison.calibrate()
    comparison.set(.size, to: 144, side: .a, catalog: FontCatalog())
    #expect(comparison.a.leading == 24 && comparison.b?.leading == 30)
    comparison.setLeading(nil, side: side)
    #expect(comparison.a.leading == nil && comparison.b?.leading == nil)
    #expect(comparison.link?.leadingOffset == 0)
    #expect(comparison.link?.sizeRatio == 2)
    comparison.setLeading(32, side: side)
    #expect(comparison.a.leading == 32 && comparison.b?.leading == 32)
  }

  @Test(arguments: [Side.a, .b])
  func linkingFromAutoStartsWithEqualExplicitLeading(side: Side) {
    var comparison = Comparison()
    comparison[side]?.leading = 40
    comparison.calibrate()
    #expect(comparison.link?.leadingOffset == 0)
    comparison.setLeading(32, side: side)
    #expect(comparison.a.leading == 32 && comparison.b?.leading == 32)
  }

  @Test func independentLeadingAndSingleFontEditsAreBoundedAndRejectNonfiniteValues() {
    var comparison = Comparison()
    comparison.appearanceLocked = false
    let b = comparison.b
    comparison.setLeading(30, side: .a)
    for invalid in [Double.nan, .infinity, -.infinity] {
      comparison.setLeading(invalid, side: .a)
      #expect(comparison.a.leading == 30)
    }
    comparison.setLeading(-20, side: .a)
    #expect(comparison.a.leading == 1)
    comparison.setLeading(300, side: .a)
    #expect(comparison.a.leading == 288)
    comparison.setLeading(nil, side: .a)
    #expect(comparison.a.leading == nil && comparison.b == b)
    comparison = Comparison(b: nil)
    comparison.setLeading(32, side: .a)
    #expect(comparison.a.leading == 32)
    comparison.setLeading(40, side: .b)
    #expect(comparison.a.leading == 32 && comparison.b == nil)
  }

  @Test func leadingSurvivesFontChangesAndSerialization() throws {
    var comparison = Comparison()
    comparison.setLeading(32, side: .a)
    comparison.selectFamily("Times New Roman", side: .a, catalog: FontCatalog())
    #expect(comparison.a.leading == 32 && comparison.b?.leading == 32)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    #expect(
      try decoder.decode(FontConfiguration.self, from: encoder.encode(comparison.a))
        == comparison.a)
    comparison.setLeading(nil, side: .a)
    let automatic = try encoder.encode(comparison.a)
    #expect(!String(decoding: automatic, as: UTF8.self).contains("leading"))
    #expect(try decoder.decode(FontConfiguration.self, from: automatic) == comparison.a)
  }
}
