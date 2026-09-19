import Foundation
import Testing

@testable import TypefaceCore

@Suite struct ComparisonTests {
  let catalog = FontCatalog()

  @Test(arguments: [true, false], [Side.a, .b])
  func appearanceResetRestoresRegularAndRespectsTheLock(locked: Bool, side: Side) {
    var state = Comparison(a: .init("HelveticaNeue-BoldItalic"), b: .init("Arial-BoldItalicMT"))
    state.appearanceLocked = locked
    state.a.size = 44
    state.b?.tracking = 0.05
    state.a.features = ["ot.kern": 0]
    state.b?.features = ["ot.liga": 0]
    state.calibrate()
    let previous = state
    state.resetAppearance(side: side, catalog: catalog)
    for target in [Side.a, .b] {
      if locked || side == target {
        #expect(state[target]?.face.italic == false)
        #expect(state[target]?.weight == 400)
        #expect(state[target]?.size == 22)
        #expect(state[target]?.tracking == 0)
        #expect(state[target]?.features == previous[target]?.features)
      } else {
        #expect(state[target] == previous[target])
      }
    }
    #expect(state.link == AppearanceLink(a: state.a, b: state.b!))
  }

  @Test func appearanceResetUsesActualAxisDefaultsAndPreservesMissingFonts() throws {
    let skia = try #require(catalog.preferredFace(in: "Skia"))
    var state = Comparison(a: .init(skia.id), b: nil)
    for axis in skia.axes { state.a.axes[axis.id] = axis.maximum }
    state.resetAppearance(side: .a, catalog: catalog)
    for axis in skia.axes { #expect(state.a.axes[axis.id] == axis.defaultValue) }
    state.a = .init("TypefaceOff-Does-Not-Exist")
    state.a.size = 44
    state.a.tracking = 0.02
    state.resetAppearance(side: .a, catalog: catalog)
    #expect(state.a.postScriptName == "TypefaceOff-Does-Not-Exist")
    #expect(!FontRenderer.isAvailable(state.a))
    #expect(state.a.size == 22 && state.a.tracking == 0)
  }

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

  @Test(.enabled(if: FontCatalog().preferredFace(in: "Inter Variable") != nil))
  func sharedOpticalSizeCalibrationWorksInBothDirectionsAndSurvivesClamping() throws {
    let face = try #require(catalog.preferredFace(in: "Inter Variable"))
    let axis = try #require(face.axes.first { $0.tag == "opsz" })
    var state = Comparison(a: .init(face.id), b: .init(face.id))
    state.a.axes[axis.id] = axis.minimum
    state.b?.axes[axis.id] = axis.minimum + 2
    state.calibrate()
    state.set(.axis(axis.id), to: axis.maximum, side: .a, catalog: catalog)
    #expect(state.b?.axes[axis.id] == axis.maximum)
    state.set(.axis(axis.id), to: axis.minimum + 4, side: .a, catalog: catalog)
    #expect(state.b?.axes[axis.id] == axis.minimum + 6)
    state.set(.axis(axis.id), to: axis.minimum + 3, side: .b, catalog: catalog)
    #expect(state.a.axes[axis.id] == axis.minimum + 1)
    state.swap()
    #expect(state.link?.axisOffsets[axis.id] == -2)
    state.set(.axis(axis.id), to: axis.minimum + 4, side: .a, catalog: catalog)
    #expect(state.b?.axes[axis.id] == axis.minimum + 2)
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

  @Test func matchingRequiresBothConfiguredFontsToBeInstalled() {
    let missing = FontConfiguration("TypefaceOff-Does-Not-Exist")
    for comparison in [Comparison(a: missing), Comparison(b: missing), Comparison(b: nil)] {
      #expect(Matching.proposal(comparison, options: MatchOptions(), catalog: catalog) == nil)
    }
  }
}
