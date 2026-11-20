import AppKit
import CoreText
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct SpecificationHeaderTests {
  @Test(arguments: [960.0, 1024, 1119, 1440], [false, true])
  func compactTypographyStaysAccessible(width: Double, inspectorOpen: Bool) async throws {
    let model = WorkbenchModel()
    var opened: ComparisonInspectorState.Section?
    let host = WorkbenchTestHost(
      SpecificationHeader(
        model: model, inspectorOpen: inspectorOpen, matching: false,
        openInspector: { opened = $0 }, match: {}), width: width, height: 106)
    defer { host.window.close() }
    try await host.settle()
    let compact = width < 1120 || inspectorOpen
    let target = compact ? "Open typography inspector" : "Font B typography"
    let button = try await host.element(target)
    let frame = try #require(button.accessibilityFrame?())
    let match = try #require(try await host.element("Match…").accessibilityFrame?())
    #expect(frame.width >= 20 && frame.height >= 20 && !frame.intersects(match))
    let tracking = try #require(
      host.subviews.compactMap { $0 as? SpecificationFieldView }.first {
        $0.field.accessibilityIdentifier() == "Font A Tracking field"
      })
    #expect(
      !frame.intersects(host.window.convertToScreen(tracking.convert(tracking.bounds, to: nil))))
    try await host.press(target)
    #expect(opened == .typography)
    if compact {
      host.setContent(
        SpecificationHeader(
          model: model, inspectorOpen: inspectorOpen, matching: true,
          openInspector: { opened = $0 }, match: {}))
      try await host.settle()
      #expect(!host.isEnabled("Open typography inspector"))
    }
  }

  @Test(arguments: [960.0, 1440])
  func changedAxesOpenAppearanceAndDisappearAfterReset(width: Double) async throws {
    let url = try #require(
      Bundle(for: HeaderFixtureBundle.self).url(forResource: "OpticalSize", withExtension: "ttf"))
    try #require(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
    defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
    let config = FontConfiguration("TypefaceOffRegionOptical-Regular")
    let model = WorkbenchModel(comparison: Comparison(a: config, b: config), catalog: FontCatalog())
    model.comparison.resetAppearance(catalog: model.catalog)
    var opened: ComparisonInspectorState.Section?
    var matching = false
    let makeView = {
      SpecificationHeader(
        model: model, inspectorOpen: false, matching: matching,
        openInspector: { opened = $0 }, match: {}
      ).background(WorkbenchStyle.paper)
    }
    let host = WorkbenchTestHost(makeView(), width: width, height: 106)
    defer { host.window.close() }
    try await host.settle()
    #expect(!host.isEnabled("Font A other axes"))
    for (id, value, count) in [(tagNumber("opsz"), 30.0, 1), (tagNumber("wdth"), 80.0, 2)] {
      model.comparison.a.axes[id] = value
      model.comparison.b?.axes[id] = value
      try await host.settle()
      for side in [Side.a, .b] {
        let button = try await host.element("\(side.fontName) other axes")
        let frame = try #require(button.accessibilityFrame?())
        #expect(frame.width >= 20 && frame.height >= 20)
        let description: String? = button.accessibilityValue?()
        #expect(description == "\(count) changed \(count == 1 ? "axis" : "axes"), opens Appearance")
        try await host.press("\(side.fontName) other axes")
        #expect(opened == .appearance)
      }
    }
    if let folder = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] {
      let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
      host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: folder).appendingPathComponent("axes-header-\(Int(width)).png"))
    }
    matching = true
    host.setContent(makeView())
    try await host.settle()
    #expect(!host.isEnabled("Font A other axes") && !host.isEnabled("Font B other axes"))
    model.comparison.resetAppearance(catalog: model.catalog)
    matching = false
    host.setContent(makeView())
    try await host.settle()
    #expect(!host.isEnabled("Font A other axes") && !host.isEnabled("Font B other axes"))
  }

  @Test func aFamilyFocusRequestLetsReturnOpenTheCorrectPicker() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(HeaderFocusProbe(model: model))
    defer { host.window.close() }
    try await host.settle()
    for side in [Side.a, .b] {
      try await host.press("Focus \(side.fontName)")
      try await host.settle()
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: host.window.windowNumber, context: nil, characters: "\r",
          charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
      host.window.sendEvent(event)
      try await host.settle {
        host.subviews.compactMap { $0 as? NSSearchField }.contains {
          $0.placeholderString == "Search installed fonts"
        }
      }
      let current = host.subviews.compactMap { $0 as? FontFamilyRowButton }.filter(\.current)
      #expect(Set(current.map(\.title)) == [model.comparison[side]!.face.family])
      let search = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
      search.currentEditor()?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
      try await host.settle()
    }
  }

  @Test func pairedFieldsFollowTheModelAndKeepUndo() async throws {
    let model = WorkbenchModel()
    var opened: ComparisonInspectorState.Section?
    var matched = false
    let host = WorkbenchTestHost(
      SpecificationHeader(
        model: model, inspectorOpen: false, matching: false,
        openInspector: { opened = $0 }, match: { matched = true }
      ).background(WorkbenchStyle.paper).preferredColorScheme(.light), height: 106)
    defer { host.window.close() }
    try await host.settle()
    let fields = host.subviews.compactMap { $0 as? SpecificationFieldView }
    #expect(fields.count == 6)
    let a = try #require(fields.first { $0.field.accessibilityIdentifier() == "Font A Size field" })
    let b = try #require(fields.first { $0.field.accessibilityIdentifier() == "Font B Size field" })
    try await host.submit("24", to: a.field)
    #expect(model.comparison.a.size == 24 && model.comparison.b?.size == 24)
    try await host.press("Link A and B")
    #expect(!model.comparison.appearanceLocked)
    try await host.submit("21.46", to: b.field)
    try await host.settle()
    #expect(a.field.stringValue == "24.00" && b.field.stringValue == "21.46")
    try await host.press("Font B typography")
    #expect(opened == .typography)
    try await host.press("Match…")
    #expect(matched)
    try await host.press("Swap fonts")
    #expect(model.comparison.a.postScriptName == "ArialMT")
    host.window.undoManager?.undo()
    #expect(model.comparison.a.postScriptName == "HelveticaNeue")
    if let folder = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] {
      let image = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
      host.view.cacheDisplay(in: host.view.bounds, to: image)
      let data = try #require(image.representation(using: .png, properties: [:]))
      try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("header.png"))
    }
  }

  @Test(arguments: [1120.0, 1440])
  func relationsEqualizeOnlyTheirSetting(width: Double) async throws {
    var comparison = Comparison()
    comparison.b?.size = 21.5
    comparison.b?.tracking = 0.004
    comparison.a.leading = 28
    comparison.b?.leading = 27
    comparison.calibrate()
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(
      SpecificationHeader(
        model: model, inspectorOpen: true, matching: false, openInspector: { _ in }, match: {}),
      width: width, height: 106)
    defer { host.window.close() }
    try await host.settle()
    try await host.choose(
      "×0.977", nativeTitles: ["Make B Equal to A", "Make A Equal to B"], item: "Make B Equal to A")
    #expect(model.comparison.a.size == 22 && model.comparison.b?.size == 22)
    #expect(model.comparison.link?.trackingOffset == 0.004)
    try await host.choose(
      "+0.004 em", nativeTitles: ["Make B Equal to A", "Make A Equal to B"],
      item: "Make A Equal to B")
    #expect(model.comparison.a.tracking == 0.004)
    try await host.choose(
      "−1.000 pt", nativeTitles: ["Make B Equal to A", "Make A Equal to B"],
      item: "Make B Equal to A")
    #expect(model.comparison.b?.leading == 28)
  }

  @Test(arguments: [960.0, 1120, 1440])
  func missingAndSingleFontRowsHaveNoEditableValues(width: Double) async throws {
    for b in [FontConfiguration?.none, .init("TypefaceOff-Not-Installed")] {
      let model = WorkbenchModel(comparison: Comparison(b: b))
      let host = WorkbenchTestHost(
        SpecificationHeader(
          model: model, inspectorOpen: false, matching: false, openInspector: { _ in }, match: {}),
        width: width, height: 106)
      defer { host.window.close() }
      try await host.settle()
      let fields = host.subviews.compactMap { $0 as? SpecificationFieldView }
      #expect(fields.count == 3)
      #expect(fields.allSatisfy { $0.field.accessibilityIdentifier().hasPrefix("Font A") })
      #expect(host.isEnabled("Swap fonts") == (b != nil))
      #expect(!host.isEnabled("Link A and B"))
      try await host.press("Font B family")
      try await host.press("Arial")
      try await host.settle()
      #expect(model.comparison.b?.postScriptName == "ArialMT")
    }
  }

  @Test func matchingLocksFieldsAndVariableWeightIsEditable() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    for matching in [false, true] {
      let host = WorkbenchTestHost(
        SpecificationHeader(
          model: model, inspectorOpen: false, matching: matching, openInspector: { _ in }, match: {}
        ),
        height: 106)
      defer { host.window.close() }
      try await host.settle()
      let fields = host.subviews.compactMap { $0 as? SpecificationFieldView }
      #expect(fields.count == 8)
      #expect(fields.allSatisfy { $0.field.isEnabled == !matching })
      #expect(host.isEnabled("Font A family") == !matching)
    }
  }

  @Test func familyStyleAndTypographySummariesReflectTheSelectedFace() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(
      SpecificationHeader(
        model: model, inspectorOpen: false, matching: false, openInspector: { _ in }, match: {}),
      height: 106)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Font A family")
    try await host.settle()
    let search = try #require(
      host.subviews.compactMap { $0 as? NSTextField }.first {
        $0.placeholderString == "Search installed fonts"
      })
    search.currentEditor()?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    try await host.settle()
    try await host.press("Font A family")
    let reopened = try #require(
      host.subviews.compactMap { $0 as? NSSearchField }.first {
        $0.placeholderString == "Search installed fonts"
      })
    host.enter("Arial", in: reopened)
    try await host.settle()
    try await host.press("Arial")
    try await host.settle()
    #expect(model.comparison.a.face.family == "Arial")
    let styles = model.catalog.faces(in: "Arial").map(\.style)
    try await host.choose("Font A style", nativeTitles: styles, item: "Bold")
    #expect(model.comparison.a.postScriptName == "Arial-BoldMT")
    let features = Array(
      model.comparison.a.face.features.filter { feature in
        feature.options.contains { $0.value != feature.defaultValue }
      }.prefix(2))
    try #require(features.count == 2)
    for (index, feature) in features.enumerated() {
      let value = try #require(feature.options.first { $0.value != feature.defaultValue }?.value)
      model.edit("Change typography", undoManager: nil) { $0.a.features[feature.id] = value }
      try await host.settle()
      let valueDescription: String? = try await host.element("Font A typography")
        .accessibilityValue?()
      #expect(
        valueDescription
          == "\(index + 1) \(index == 0 ? "change" : "changes"), opens the inspector")
    }
  }

  @Test func axisAndAutomaticLeadingRelationsCanBeEqualized() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    var comparison = Comparison(a: .init(name), b: .init(name))
    let weight = tagNumber("wght")
    comparison.b?.axes[weight] = comparison.a.weight + 0.2
    comparison.b?.leading = 30
    comparison.calibrate()
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(
      SpecificationHeader(
        model: model, inspectorOpen: false, matching: false, openInspector: { _ in }, match: {}),
      height: 106)
    defer { host.window.close() }
    try await host.settle()
    try await host.choose(
      "+0.2", nativeTitles: ["Make B Equal to A", "Make A Equal to B"], item: "Make B Equal to A")
    #expect(model.comparison.a.weight == model.comparison.b?.weight)
    model.edit("Calibrate leading", undoManager: nil) { $0.link?.leadingOffset = 1 }
    try await host.settle()
    try await host.choose(
      "+1.000 pt", nativeTitles: ["Make B Equal to A", "Make A Equal to B"],
      item: "Make B Equal to A")
    #expect(model.comparison.a.leading == nil && model.comparison.b?.leading == nil)
  }
}

private final class HeaderFixtureBundle: NSObject {}

private struct HeaderFocusProbe: View {
  let model: WorkbenchModel
  @State private var target: Side?

  var body: some View {
    VStack {
      ForEach([Side.a, .b], id: \.self) { side in
        Button("Focus \(side.fontName)") { target = side }
      }
      SpecificationHeader(
        model: model, inspectorOpen: false, matching: false,
        familyFocus: $target, openInspector: { _ in }, match: {})
    }
  }
}
