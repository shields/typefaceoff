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
