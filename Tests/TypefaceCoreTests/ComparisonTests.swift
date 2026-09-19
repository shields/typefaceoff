import Foundation
import Testing

@testable import TypefaceCore

@Suite struct ComparisonTests {
  let catalog = FontCatalog()

  @Test func linkedStyleSelectionPreservesEquallyWeightedFaces() {
    var state = Comparison(b: .init("HelveticaNeue-CondensedBold"))
    state.selectFace(.named("HelveticaNeue-CondensedBold"), side: .a, catalog: catalog)
    #expect(state.a.postScriptName == "HelveticaNeue-CondensedBold")
    // Recalibrate to test the same tie on the other side of the link.
    state.b = .init("HelveticaNeue-CondensedBold")
    state.calibrate()
    state.selectFace(.named("HelveticaNeue-Bold"), side: .a, catalog: catalog)
    #expect(state.b?.postScriptName == "HelveticaNeue-CondensedBold")
    state.a.set(.weight, to: 650, catalog: catalog)
    #expect(state.a.postScriptName == "HelveticaNeue-Bold")
    state.a.set(.weight, to: 400, catalog: catalog)
    #expect(state.a.weight == 400)
  }

  @Test(arguments: [0.03, -0.03], [true, false])
  func trackingMatchMeasuresShapedLigatures(tracking: Double, explicitLigatures: Bool) throws {
    var state = Comparison(a: .init("HelveticaNeue"), b: .init("HelveticaNeue"))
    state.sample = .custom
    state.customText = "fififififi"
    state.a.features["aat.1.2"] = 3
    state.a.tracking = tracking
    if explicitLigatures { state.b?.features["aat.1.2"] = 2 }
    var options = MatchOptions()
    options.weight = false
    options.tracking = true
    let proposed = try #require(Matching.proposal(state, options: options, catalog: catalog))
    let target = FontRenderer.measure(state.text, config: state.a, size: 22, tracking: true).advance
    let result = FontRenderer.measure(state.text, config: proposed, size: 22, tracking: true)
      .advance
    #expect(abs(target - result) < 0.001)
    #expect(state.b?.tracking == 0)
  }

  @Test func trackingMatchClampsToAllowedRange() throws {
    var state = Comparison(a: .init("HelveticaNeue"), b: .init("HelveticaNeue"))
    state.sample = .custom
    state.customText = "fififififi"
    state.a.size = 144
    state.b?.size = 10
    var options = MatchOptions()
    options.weight = false
    options.tracking = true
    let proposed = try #require(Matching.proposal(state, options: options, catalog: catalog))
    #expect(abs(proposed.tracking - 0.15) < 1e-9)
  }

  @Test func staticWeightAndItalicLinkUseRealFaces() {
    var state = Comparison()
    let bold = FontFace.named("HelveticaNeue-Bold")
    #expect(bold.weight == 700)
    state.selectFace(bold, side: .a, catalog: catalog)
    #expect(state.b?.postScriptName == "Arial-BoldMT")
    state.selectFace(FontFace.named("HelveticaNeue-Italic"), side: .a, catalog: catalog)
    #expect(state.b?.face.italic == true)
    state.selectFamily("Arial", side: .a, catalog: catalog)
    #expect(state.a.face.italic)
  }

  @Test func linkedSizeAndTrackingPreserveCalibration() throws {
    var state = Comparison()
    state.b?.size = 24
    state.b?.tracking = 0.02
    state.calibrate()
    state.set(.size, to: 44, side: .a, catalog: catalog)
    #expect(state.b?.size == 48)
    state.set(.tracking, to: 0.03, side: .b, catalog: catalog)
    #expect(abs(state.a.tracking - 0.01) < 1e-9)
    state.set(.size, to: 144, side: .a, catalog: catalog)
    #expect(state.b?.size == 144)
    state.set(.size, to: 22, side: .a, catalog: catalog)
    #expect(state.b?.size == 24)
  }

  @Test func unlockingAndIndependentFeatures() throws {
    var state = Comparison()
    state.appearanceLocked = false
    state.set(.tracking, to: 0.1, side: .a, catalog: catalog)
    #expect(state.b?.tracking == 0)
    let feature = try #require(state.a.face.features.first { $0.id == "ot.kern" })
    state.setFeature(feature, value: 0, side: .a)
    #expect(state.b?.features.isEmpty == true)
  }

  @Test func singleFontRestoresCompleteConfiguration() {
    var state = Comparison()
    state.b?.size = 31
    state.b?.features = ["ot.liga": 0]
    let saved = state.b
    state.selectFamily(nil, side: .b, catalog: catalog)
    #expect(state.b == nil)
    state.selectFamily("Arial", side: .b, catalog: catalog)
    #expect(state.b == saved)
    state.swap()
    #expect(state.a == saved)
    #expect(state.b?.postScriptName == "HelveticaNeue")
  }

  @Test func savedComparisonRoundTripsAndRejectsInvalidInput() throws {
    var state = Comparison()
    state.customText = "*literal* _text_ 🐇 e\u{301}"
    state.sample = .custom
    state.selectedGlyph = "e\u{301}"
    #expect(try Comparison.decode(state.encoded()) == state)
    state.a.size = -1
    #expect(throws: ComparisonFileError.self) { try Comparison.decode(state.encoded()) }
    #expect(throws: (any Error).self) { try Comparison.decode(Data("{}".utf8)) }
  }

  @Test(.enabled(if: FontCatalog().preferredFace(in: "Inter Variable") != nil))
  func variableWeightCalibrationSurvivesClamping() throws {
    let face = try #require(catalog.preferredFace(in: "Inter Variable"))
    #expect(!face.axes.isEmpty)
    var state = Comparison(a: .init(face.id), b: .init(face.id))
    state.b?.set(.weight, to: 380, catalog: catalog)
    state.calibrate()
    state.set(.weight, to: 500, side: .a, catalog: catalog)
    #expect(state.b?.weight == 480)
    let bold = try #require(catalog.faces(in: "Inter Variable").first { $0.style == "Bold" })
    state.selectFace(bold, side: .a, catalog: catalog)
    #expect(state.a.weight == 700)
    #expect(state.b?.weight == 680)
    state.set(.weight, to: 100, side: .a, catalog: catalog)
    state.set(.weight, to: 500, side: .a, catalog: catalog)
    #expect(state.b?.weight == 480)
  }

  @Test func matchingMeasuresXHeightAndDoesNotMutateSource() throws {
    let state = Comparison()
    var options = MatchOptions()
    options.xHeight = true
    let proposed = try #require(Matching.proposal(state, options: options, catalog: catalog))
    let aHeight = FontRenderer.measure("x", config: state.a, size: state.a.size).bounds.height
    let bHeight = FontRenderer.measure("x", config: proposed, size: proposed.size).bounds.height
    #expect(abs(aHeight - bHeight) < 0.001)
    #expect(state.b?.size == 22)
  }
}
