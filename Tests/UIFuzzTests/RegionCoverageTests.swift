import Testing

@testable import UIFuzzSupport

@Suite struct RegionCoverageTests {
  @Test(arguments: ["Font A", "Font B"])
  func familyButtonsNeedNoInspectorAndSpecimenScrollAreasNeedText(font: String) {
    #expect(
      WorkbenchState.requirement(of: .init(kind: .press, target: "\(font) family"))
        == .family(font == "Font A" ? .a : .b))
    #expect(
      WorkbenchState.requirement(of: .init(kind: .scroll, target: "\(font) specimen scroll area"))
        == .mode(.text))
  }
}
