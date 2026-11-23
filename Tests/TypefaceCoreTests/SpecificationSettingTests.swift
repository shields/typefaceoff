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

import Foundation
import Testing

@testable import TypefaceCore

@Suite struct SpecificationSettingTests {
  let catalog = FontCatalog()

  @Test func valuesAndRangesFollowTheFont() throws {
    let config = FontConfiguration("HelveticaNeue")
    #expect(SpecificationSetting.size.value(in: config) == 22)
    #expect(SpecificationSetting.leading.value(in: config) == FontRenderer.automaticLeading(config))
    #expect(SpecificationSetting.tracking.value(in: config) == 0)
    let weight = SpecificationSetting.axis(tagNumber("wght"))
    #expect(weight.value(in: config) == 400)
    #expect(weight.rules(for: config) == nil)
    let variable = FontConfiguration(try #require(catalog.preferredFace(in: "Skia")).id)
    let axis = try #require(variable.face.axes.first)
    #expect(
      SpecificationSetting.axis(axis.id).rules(for: variable)?.range == axis.minimum...axis.maximum)
    #expect(SpecificationSetting.axis(axis.id).value(in: variable) == variable.axes[axis.id])
    var defaults = variable
    defaults.axes = [:]
    let width = try #require(variable.face.axes.first { $0.tag == "wdth" })
    #expect(SpecificationSetting.axis(width.id).value(in: defaults) == width.defaultValue)
  }

  @Test(arguments: [Side.a, .b])
  func linkedEditsKeepCalibratedRelationshipsAndEqualizingKeepsOtherCalibration(side: Side) {
    var state = Comparison()
    state.b?.size = 44
    state.b?.tracking = 0.04
    state.a.leading = 24
    state.b?.leading = 30
    state.calibrate()
    #expect(
      SpecificationSetting.size.apply(
        .number(100), to: &state, side: .a, both: false, catalog: catalog))
    #expect(state.b?.size == 144)
    #expect(
      SpecificationSetting.tracking.apply(
        .number(0), to: &state, side: side, both: true, catalog: catalog))
    #expect(state.a.tracking == 0 && state.b?.tracking == 0)
    #expect(state.link?.sizeRatio == 2 && state.link?.leadingOffset == 6)
    #expect(state.link?.trackingOffset == 0)
    #expect(
      SpecificationSetting.size.apply(
        .number(22), to: &state, side: .a, both: false, catalog: catalog))
    #expect(state.b?.size == 44)
    #expect(
      SpecificationSetting.size.apply(
        .number(32), to: &state, side: side, both: true, catalog: catalog))
    #expect(state.a.size == 32 && state.b?.size == 32 && state.link?.sizeRatio == 1)
    #expect(state.link?.leadingOffset == 6)
    #expect(
      SpecificationSetting.leading.apply(
        .number(28), to: &state, side: side, both: true, catalog: catalog))
    #expect(state.a.leading == 28 && state.b?.leading == 28 && state.link?.leadingOffset == 0)
    #expect(
      SpecificationSetting.leading.apply(
        .automatic, to: &state, side: side, both: false, catalog: catalog))
    #expect(state.a.leading == nil && state.b?.leading == nil)
  }

  @Test func rejectedEntriesLeaveTheEntireComparisonUntouched() {
    var state = Comparison()
    let before = state
    for entry in [SpecificationValue.Entry.automatic, .number(9), .number(145), .number(.nan)] {
      #expect(
        !SpecificationSetting.size.apply(entry, to: &state, side: .a, both: true, catalog: catalog))
      #expect(state == before)
    }
    #expect(
      !SpecificationSetting.axis(tagNumber("wght")).apply(
        .number(500), to: &state, side: .a, both: false, catalog: catalog))
    #expect(state == before)
    state.b = nil
    #expect(
      !SpecificationSetting.size.apply(
        .number(22), to: &state, side: .b, both: false, catalog: catalog))
    state.b = .init("TypefaceOff-Missing")
    #expect(
      !SpecificationSetting.size.apply(
        .number(22), to: &state, side: .b, both: false, catalog: catalog))
  }

  @Test func absentFontsSuspendTheLinkAndSingleFontEditsStillWork() {
    var state = Comparison(b: .init("TypefaceOff-Missing"))
    let missing = state.b
    #expect(
      SpecificationSetting.size.apply(
        .number(30), to: &state, side: .a, both: false, catalog: catalog))
    #expect(state.a.size == 30 && state.b == missing && state.appearanceLocked)
    state.b = nil
    #expect(
      SpecificationSetting.leading.apply(
        .number(32), to: &state, side: .a, both: true, catalog: catalog))
    #expect(state.a.leading == 32 && state.b == nil)
    state = Comparison()
    state.appearanceLocked = false
    #expect(
      SpecificationSetting.tracking.apply(
        .number(0.01), to: &state, side: .b, both: false, catalog: catalog))
    #expect(state.a.tracking == 0 && state.b?.tracking == 0.01 && !state.appearanceLocked)
  }

  @Test func axisEditsOnlyEqualizeAxesPresentInBothFonts() throws {
    let name = try #require(catalog.preferredFace(in: "Skia")).id
    var state = Comparison(a: .init(name), b: .init(name))
    for axis in state.a.face.axes {
      let setting = SpecificationSetting.axis(axis.id)
      #expect(
        setting.apply(.number(axis.maximum), to: &state, side: .a, both: false, catalog: catalog))
      #expect(state.b?.axes[axis.id] == axis.maximum)
      #expect(
        setting.apply(.number(axis.minimum), to: &state, side: .b, both: true, catalog: catalog))
      #expect(state.a.axes[axis.id] == axis.minimum && state.b?.axes[axis.id] == axis.minimum)
      #expect(state.link?.axisOffsets[axis.id] == 0)
    }
    #expect(state.link?.weightOffset == 0)
    state.b = .init("HelveticaNeue")
    let before = state
    let axis = try #require(state.a.face.axes.first)
    #expect(
      !SpecificationSetting.axis(axis.id).apply(
        .number(axis.minimum), to: &state, side: .a, both: true, catalog: catalog))
    #expect(state == before)
  }
}
