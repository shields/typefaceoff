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

import AppKit
import SwiftUI
import Testing

@testable import TypefaceCore
@testable import TypefaceOff

@Suite(.serialized) @MainActor struct ComparisonInspectorTests {
  @Test func reopeningRestoresScrollDisclosureAndSelectionState() async throws {
    let model = WorkbenchModel()
    model.inspector.selectedFeature = "ot.kern"
    model.inspector.collapsedGroups.insert(.numbers)
    let host = WorkbenchTestHost(
      VisibilityFixture(model: model, visible: true), width: 320, height: 400)
    defer { host.window.close() }
    try await host.settle()
    let scroll = try #require(host.subviews.compactMap { $0 as? NSScrollView }.first)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 80))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await host.settle()
    let y = scroll.contentView.bounds.minY
    #expect(y > 0)
    host.setContent(VisibilityFixture(model: model, visible: false))
    try await host.settle()
    host.setContent(VisibilityFixture(model: model, visible: true))
    try await host.settle()
    let restored = try #require(host.subviews.compactMap { $0 as? NSScrollView }.first)
    #expect(
      abs(restored.contentView.bounds.minY - y) < 1,
      "Scroll offset \(y) restored as \(restored.contentView.bounds.minY)")
    #expect(model.inspector.selectedFeature == "ot.kern")
    #expect(model.inspector.collapsedGroups.contains(.numbers))
  }

  @Test func appearancePairsKeepCalibrationAndAutoCanBeDragged() async throws {
    var comparison = Comparison()
    comparison.b?.size = 21.5
    comparison.b?.tracking = 0.004
    comparison.calibrate()
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(
      ComparisonInspector(model: model, state: model.inspector).preferredColorScheme(.light),
      width: 320, height: 850)
    defer { host.window.close() }
    try await host.settle()
    let fields = host.subviews.compactMap { $0 as? SpecificationFieldView }
    let a = try #require(
      fields.first { $0.field.accessibilityIdentifier() == "Font A Inspector Size field" })
    let b = try #require(
      fields.first { $0.field.accessibilityIdentifier() == "Font B Inspector Size field" })
    #expect(a.field.stringValue == "22.0" && b.field.stringValue == "21.5")
    let sliders = host.subviews.compactMap { $0 as? SpecificationSliderView }
    #expect(sliders.count == 6)
    let leading = try #require(sliders.first { $0.accessibilityIdentifier() == "Font A Leading" })
    #expect((leading.cell as? SpecificationSliderCell)?.automatic == true)
    #expect(leading.toolTip?.contains("Auto off") == true)
    _ = leading.accessibilityPerformIncrement()
    try await host.settle()
    #expect(model.comparison.a.leading != nil && model.comparison.b?.leading != nil)
    #expect((leading.cell as? SpecificationSliderCell)?.automatic == false)
    try await host.press("Font A Auto leading")
    #expect(model.comparison.a.leading == nil && model.comparison.b?.leading == nil)
    try await host.press("Font A Auto leading")
    #expect(model.comparison.a.leading != nil)
    try await host.press("Reset paired leading")
    #expect(model.comparison.a.leading == nil)
    try await host.choose(
      "×0.977", nativeTitles: ["Make B Equal to A", "Make A Equal to B"], item: "Make B Equal to A")
    #expect(model.comparison.a.size == model.comparison.b?.size)
    try await host.press("Reset paired tracking")
    #expect(model.comparison.a.tracking == 0 && model.comparison.b?.tracking == 0)
    try await host.press("Inspector appearance link")
    try await host.submit("25", to: b.field)
    #expect(model.comparison.b?.size == 25 && model.comparison.a.size == 22)
    host.window.undoManager?.removeAllActions()
    try await host.press("Reset appearance section")
    #expect(model.comparison.b?.size == 22 && !model.comparison.appearanceLocked)
    host.window.undoManager?.undo()
    #expect(model.comparison.b?.size == 25)
    try await host.settle()
    if let folder = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] {
      let image = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
      host.view.cacheDisplay(in: host.view.bounds, to: image)
      try #require(image.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: folder).appendingPathComponent("inspector.png"))
    }
  }

  @Test func typographyIsPairedAndRemembersItsSelectionAndDisclosures() async throws {
    let model = WorkbenchModel()
    model.inspector.reveal(.typography)
    let host = WorkbenchTestHost(
      ComparisonInspector(model: model, state: model.inspector).preferredColorScheme(.light),
      width: 320, height: 400)
    defer { host.window.close() }
    try await host.settle {
      host.subviews.compactMap { $0 as? NSScrollView }.contains {
        $0.contentView.bounds.minY > 100
      }
    }
    try await host.press("Font B feature ot.kern")
    #expect(model.comparison.b?.features["ot.kern"] == 0)
    #expect(model.comparison.a.features["ot.kern"] == nil)
    #expect(model.inspector.selectedFeature == "ot.kern")
    try await host.settle()
    #expect(!host.subviews.compactMap { $0 as? FontPreviewDrawingView }.isEmpty)
    try await host.press("Reset feature ot.kern")
    #expect(model.comparison.b?.features["ot.kern"] == nil)
    try await host.press("Font A feature ot.kern")
    try await host.press("Reset typography section")
    #expect(model.comparison.a.features.isEmpty && model.comparison.b?.features.isEmpty == true)
    try await host.press("Font B feature ot.dlig")
    #expect(model.comparison.b?.features["ot.dlig"] == 1)
    try await host.settle()
    try await host.press("Reset feature ot.dlig")
    let numbers = try #require(model.comparison.a.face.features.first { $0.id == "aat.6" })
    let option = try #require(numbers.options.first { $0.value != numbers.defaultValue })
    try await host.choose(
      "Font A feature aat.6", nativeTitles: numbers.options.map(\.name), item: option.name)
    #expect(model.comparison.a.features[numbers.id] == option.value)
    try await host.press("Select typography aat.17")
    try await host.settle()
    try await host.press("Select typography ot.kern")
    #expect(model.inspector.selectedFeature == "ot.kern")
    try await host.press("Common")
    #expect(model.inspector.collapsedGroups.contains(.common))
    try await host.press("Common")
    #expect(!model.inspector.collapsedGroups.contains(.common))
    try await host.press("Automatic shaping")
    #expect(!model.inspector.collapsedGroups.contains(.automatic))
    model.inspector.reveal(.appearance)
    try await host.settle()
  }

  @Test func missingAndVariableFontsHaveOnlySupportedControls() async throws {
    let variable = try #require(FontCatalog().preferredFace(in: "Skia")).id
    for comparison in [
      Comparison(a: .init(variable), b: .init(variable)),
      Comparison(a: .init("HelveticaNeue"), b: .init(variable)),
      Comparison(a: .init(variable), b: nil),
      Comparison(a: .init("TypefaceOff-Not-Installed"), b: .init("ArialMT")),
      Comparison(a: .init("NotoSansSyriac-Regular"), b: .init("ArialMT")),
    ] {
      let model = WorkbenchModel(comparison: comparison)
      let host = WorkbenchTestHost(
        ComparisonInspector(model: model, state: model.inspector).preferredColorScheme(.light),
        width: 320, height: 850)
      defer { host.window.close() }
      try await host.settle()
      let expected = [comparison.a, comparison.b].compactMap { $0 }.filter {
        FontRenderer.isAvailable($0)
      }.reduce(0) { $0 + 3 + $1.face.axes.count }
      #expect(host.subviews.compactMap { $0 as? SpecificationSliderView }.count == expected)
      for side in [Side.a, .b] {
        guard let config = comparison[side], FontRenderer.isAvailable(config) else { continue }
        for axis in config.face.axes {
          let slider = try #require(
            host.subviews.compactMap { $0 as? SpecificationSliderView }.first {
              $0.accessibilityIdentifier() == "\(side.fontName) \(axis.name)"
            })
          slider.setAccessibilityValue(axis.maximum)
          try await host.settle()
          #expect(model.comparison[side]?.axes[axis.id] == axis.maximum)
          try await host.press("Reset paired \(axis.name.lowercased())")
          #expect(model.comparison[side]?.axes[axis.id] == axis.defaultValue)
        }
      }
    }
  }

  @Test func unavailablePreviewsAndFontsKeepTheirMissingState() async throws {
    let feature = FontFeature(
      id: "ot.test", name: "Unrecognized feature",
      options: [.init(name: "Off", value: 0), .init(name: "On", value: 1)], defaultValue: 0)
    let preview = WorkbenchTestHost(
      InspectorFeaturePreview(feature: feature, config: .init("ArialMT"), side: .a),
      width: 300, height: 30)
    defer { preview.window.close() }
    try await preview.settle()
    _ = try await preview.element("Font A no preview for ot.test")

    var comparison = Comparison(b: .init("TypefaceOff-Not-Installed"))
    comparison.a.features["ot.kern"] = 0
    comparison.b?.features["ot.kern"] = 0
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(
      ComparisonInspector(model: model, state: model.inspector), width: 320)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Reset feature ot.kern")
    #expect(model.comparison.a.features.isEmpty && model.comparison.b == comparison.b)
    model.comparison.a.features["ot.kern"] = 0
    try await host.settle()
    try await host.press("Reset typography section")
    #expect(model.comparison.a.features.isEmpty && model.comparison.b == comparison.b)
  }

  private struct VisibilityFixture: View {
    let model: WorkbenchModel
    let visible: Bool

    var body: some View {
      Group {
        if visible {
          ComparisonInspector(model: model, state: model.inspector)
        } else {
          Color.clear
        }
      }.preferredColorScheme(.light)
    }
  }
}
