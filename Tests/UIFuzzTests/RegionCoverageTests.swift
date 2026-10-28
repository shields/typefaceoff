import Testing

@testable import UIFuzzSupport

@Suite struct RegionCoverageTests {
  @Test(arguments: ["Font A", "Font B"])
  func inspectorHeadingsNeedNoModeAndSpecimenScrollAreasNeedText(font: String) {
    #expect(WorkbenchState.requirement(of: .init(kind: .press, target: "\(font) inspector")) == nil)
    #expect(
      WorkbenchState.requirement(of: .init(kind: .scroll, target: "\(font) specimen scroll area"))
        == .mode(.text))
  }
}
