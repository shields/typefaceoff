import Testing

@testable import TypefaceCore

@Suite struct SpecificationLayoutTests {
  @Test func fullWidthColumnsMatchTheApprovedGrid() {
    let layout = SpecificationLayout(width: 1440, inspectorOpen: false)
    #expect(layout.width == 1440 && !layout.compact && layout.showsTypography)
    #expect(layout.style == 384 && layout.size == 752 && layout.weight == 840)
    #expect(layout.leading == 912 && layout.tracking == 1016 && layout.typography == 1152)
    #expect(layout.indexControls == 1152)
    #expect(layout.familyWidth == 304 && layout.styleWidth == 336)
    #expect(layout.weightFieldWidth == 66 && layout.trackingFieldWidth == 122)
  }

  @Test func theInspectorUsesTheCompactGridAndTakesOverTypography() {
    let layout = SpecificationLayout(width: 1120, inspectorOpen: true)
    #expect(layout.compact && !layout.showsTypography)
    #expect(layout.style == 320 && layout.size == 592 && layout.weight == 680)
    #expect(layout.leading == 744 && layout.tracking == 840 && layout.typography == 936)
    #expect(layout.indexControls == 840)
    #expect(layout.familyWidth == 240 && layout.styleWidth == 240)
    #expect(layout.weightFieldWidth == 58 && layout.trackingFieldWidth == 90)
    #expect(SpecificationLayout(width: 1440, inspectorOpen: true).compact)
    let withoutInspector = SpecificationLayout(width: 1120, inspectorOpen: false)
    #expect(withoutInspector.showsTypography && withoutInspector.indexControls == 840)
  }

  @Test func narrowWindowsRetainTheNumericColumns() {
    let layout = SpecificationLayout(width: 960, inspectorOpen: false)
    #expect(layout.compact && !layout.showsTypography)
    #expect(layout.size == 512 && layout.weight == 600)
    #expect(layout.leading == 664 && layout.tracking == 760)
    #expect(layout.indexControls == 760)
    #expect(SpecificationLayout(width: 1000, inspectorOpen: false).showsTypography)
    #expect(SpecificationLayout(width: 1239, inspectorOpen: false).compact)
    #expect(!SpecificationLayout(width: 1240, inspectorOpen: false).compact)
  }
}
