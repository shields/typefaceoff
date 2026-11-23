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
import TypefaceCore

@testable import TypefaceOff

/// The fuzzer records these names and finds controls by them, so they are a contract.
@Suite(.serialized) @MainActor struct AccessibilityIdentifierTests {
  @Test func sideNamesPrefixEveryPerInspectorIdentifier() {
    #expect(Side.a.fontName == "Font A")
    #expect(Side.b.fontName == "Font B")
  }

  @Test func typographyControlsCarryStableIdentifiers() async throws {
    let supported = try await Self.supportedClasses()
    let model = WorkbenchModel(comparison: Comparison(a: .init("ArialMT")))
    let host = WorkbenchTestHost(
      ComparisonInspector(model: model, state: model.inspector), width: 320, height: 900)
    defer { host.window.close() }
    try await host.settle()
    try await expectPresent(
      "Font A feature ot.kern", kind: "Toggle", supported: supported, in: host)
    let choice = model.comparison.a.face.features.first {
      !$0.isAutomatic && $0.options.map(\.name) != ["Off", "On"]
    }
    if let choice {
      try await expectPresent(
        "Font A feature \(choice.id)", kind: "Picker", supported: supported, in: host)
    }
  }

  @Test func pairedInspectorControlsCarryTheirOwnIdentifiers() async throws {
    let supported = try await Self.supportedClasses()
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Show Inspector")
    try await host.settle()
    for side in ["A", "B"] {
      for (identifier, kind) in [
        ("Font \(side) Inspector Size field", "TextField"),
        ("Font \(side) Inspector Tracking field", "TextField"), ("Font \(side) Size", "Slider"),
        ("Font \(side) Inspector Leading field", "TextField"),
        ("Font \(side) Auto leading", "Toggle"),
      ] {
        try await expectPresent(identifier, kind: kind, supported: supported, in: host)
      }
      for axis in model.comparison.a.face.axes {
        try await expectPresent(
          "Font \(side) Inspector \(axis.name) field", kind: "TextField", supported: supported,
          in: host)
        try await expectPresent(
          "Font \(side) \(axis.name)", kind: "Slider", supported: supported, in: host)
      }
    }
  }

  @Test func identifiersAreUniquePerElement() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    _ = try await host.firstRankedCharacterButton(for: model)
    let owners = Self.owners(in: host)
    // SwiftUI names images and icon-only buttons after their SF Symbol, which repeats by design.
    for (identifier, elements) in owners
    where identifier.hasPrefix("Font ") || identifier.hasSuffix(" scroll area") {
      #expect(
        elements.count == 1,
        "\(identifier) is carried by \(elements.map { String(describing: type(of: $0)) })")
    }
  }

  @Test func identifiersNeverEqualAnotherElementsLabelOrTitle() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    var comparison = Comparison(a: .init(name), b: .init(name))
    comparison.mode = .text
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    _ = try await host.firstRankedCharacterButton(for: model)
    let elements = Self.allElements(in: host)
    var reserved = Set(["Comparison inspector"])
    func collect(_ menu: NSMenu?) {
      for item in menu?.items ?? [] {
        reserved.insert(item.title)
        collect(item.submenu)
      }
    }
    collect(NSApp.mainMenu)
    let identifiers = Set(elements.map(Self.identifier).filter { !$0.isEmpty })
    for element in elements {
      // Some macOS versions put a SwiftUI text field's identifier on its cell only, while the
      // field and the cell expose the same label; they are one accessibility element.
      let own = [element, (element as? NSTextField)?.cell as AnyObject?].compactMap { $0 }.map(
        Self.identifier)
      for text in [
        Self.text(element, "accessibilityLabel"), Self.text(element, "accessibilityTitle"),
      ].compactMap({ $0 }) where !own.contains(text) && identifiers.contains(text) {
        Issue.record("\(text) names one element by label or title and another by identifier")
      }
    }
    #expect(identifiers.isDisjoint(with: reserved))
  }

  @Test func languageIdentifiersAreUniqueAndDisjointFromOtherNames() async throws {
    let browser = LanguageBrowserModel()
    browser.selection = "eng"
    browser.filter.query = "English"
    let comparison = Comparison(a: .init("Missing-Language-Font"), b: nil)
    await browser.update(.init(comparison))
    let host = WorkbenchTestHost(
      LanguageBrowserView(
        browser: browser, comparison: comparison, inspect: { _ in }, useSpecimen: { _ in }),
      width: 960, height: 900)
    defer { host.window.close() }
    try await host.settle()
    _ = try await host.element("Language base missing scroll area")
    try await host.press("Language sources disclosure")
    try await host.settle()
    let elements = Self.allElements(in: host)
    let identifiers = Set(elements.map(Self.identifier).filter { $0.hasPrefix("Language ") })
    for (identifier, owners) in Dictionary(grouping: elements, by: Self.identifier)
    where identifiers.contains(identifier) {
      let descriptions = owners.map { element in
        let value: String? =
          element.accessibilityRole?() == .staticText ? element.accessibilityValue?() : nil
        return "\(element.accessibilityRole?()?.rawValue ?? "") / \(value ?? "")"
      }
      #expect(
        owners.count == 1,
        "\(identifier) is carried by \(descriptions)"
      )
    }
    for element in elements {
      let own = Self.identifier(of: element)
      for label in [
        Self.text(element, "accessibilityLabel"), Self.text(element, "accessibilityTitle"),
      ].compactMap({ $0 })
      where label != own {
        #expect(!identifiers.contains(label), "\(label) aliases another element")
      }
    }
    #expect(identifiers.contains("Language row eng"))
    #expect(identifiers.contains("Language list scroll area"))
    #expect(identifiers.contains("Language detail scroll area"))
  }

  @Test func specimenWithoutMetadataKeepsAppKitAccessibilityDefaults() {
    let baseline = NSTextView(frame: .zero)
    let specimen = SpecimenNSTextView(frame: .zero)
    #expect(specimen.accessibilityLabel() == baseline.accessibilityLabel())
    #expect(specimen.accessibilityIdentifier() == baseline.accessibilityIdentifier())
  }

  @Test func scrollAreaIdentifiersLandOnScrollViewsOnly() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Show Inspector")
    let expected = [
      "Comparison inspector scroll area",
      "Differences strip scroll area", "Font A specimen scroll area",
      "Font B specimen scroll area",
    ]
    func named() -> [String: [String]] {
      let names = host.subviews.compactMap { ($0 as? NSScrollView)?.accessibilityIdentifier() }
      return Dictionary(grouping: names.filter { !$0.isEmpty }, by: { $0 })
    }
    try await host.settle { expected.allSatisfy { named()[$0]?.count == 1 } }
    for identifier in expected {
      #expect(named()[identifier]?.count == 1, "\(identifier) in \(named().keys.sorted())")
    }
    let others = Self.allElements(in: host).filter { !($0 is NSScrollView) }
    for element in others {
      #expect(!Self.identifier(of: element).hasSuffix("scroll area"))
    }
    let texts = host.subviews.compactMap { $0 as? SpecimenNSTextView }
    #expect(
      Set(texts.compactMap { $0.accessibilityLabel() })
        == ["Font A specimen", "Font B specimen"])
    #expect(texts.allSatisfy { $0.accessibilityIdentifier().isEmpty })
  }

  @Test func glyphCanvasScrollAreaIsNamed() async throws {
    #expect(GlyphScrollView().accessibilityIdentifier() == "Glyph canvas scroll area")
    var comparison = Comparison()
    comparison.mode = .glyph
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel(comparison: comparison)))
    defer { host.window.close() }
    try await host.settle()
    let glyph = host.subviews.compactMap { $0 as? GlyphScrollView }
    #expect(glyph.map { $0.accessibilityIdentifier() } == ["Glyph canvas scroll area"])
    _ = try await host.element("Glyph canvas")
  }

  @Test func matchPreviewsAreDistinguishable() async throws {
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel(), matching: true))
    defer { host.window.close() }
    try await host.settle()
    let scrolls = host.subviews.compactMap { $0 as? NSScrollView }.map {
      $0.accessibilityIdentifier()
    }
    #expect(scrolls.contains("Font A specimen scroll area"))
    #expect(scrolls.contains("Font B specimen scroll area"))
    let texts = host.subviews.compactMap { $0 as? SpecimenNSTextView }
    #expect(
      texts.map { $0.accessibilityLabel()! }.sorted() == [
        "Font A specimen", "Font B specimen",
      ])
    #expect(texts.allSatisfy { $0.accessibilityIdentifier().isEmpty })
  }

  @Test func redesignedControlNamesResolve() async throws {
    let model = WorkbenchModel()
    model.comparison.a.size = 24
    model.comparison.a.features["ot.kern"] = 0
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    for label in [
      "Link A and B", "Font A family", "Font B family", "Swap fonts", "Sample selector",
    ] {
      _ = try await host.element(label)
    }
    try await host.press("Show Inspector")
    for label in [
      "Reset appearance section", "Reset paired size", "Reset typography section",
      "Inspector appearance link",
    ] {
      _ = try await host.element(label)
    }
  }

  @Test func recreatedScrollViewKeepsItsName() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(RecreatedInspector(model: model, present: true))
    defer { host.window.close() }
    try await host.settle()
    func names() -> [String] {
      host.subviews.compactMap { ($0 as? NSScrollView)?.accessibilityIdentifier() }
    }
    #expect(names() == ["Comparison inspector scroll area"])
    host.setContent(RecreatedInspector(model: model, present: false))
    try await host.settle { names().isEmpty }
    host.setContent(RecreatedInspector(model: model, present: true))
    try await host.settle { names() == ["Comparison inspector scroll area"] }
  }

  @Test func reopeningTheInspectorKeepsItsScrollAreaName() async throws {
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel()))
    defer { host.window.close() }
    try await host.settle()
    for _ in 0..<3 {
      try await host.press("Show Inspector")
      try await host.settle()
    }
    let names = host.subviews.compactMap { ($0 as? NSScrollView)?.accessibilityIdentifier() }
    #expect(names.filter { $0 == "Comparison inspector scroll area" }.count == 1)
  }

  @Test func anchorNamesTheEnclosingScrollViewWhenItsNameChanges() {
    let scroll = NSScrollView()
    let anchor = ScrollAreaAnchorView()
    #expect(anchor.enclosingScrollView == nil)
    anchor.name = "orphan"
    scroll.documentView = anchor
    #expect(scroll.accessibilityIdentifier() == "orphan")
    anchor.name = "renamed"
    #expect(scroll.accessibilityIdentifier() == "renamed")
  }

  /// The element classes whose SwiftUI identifier reaches the accessibility tree on this macOS.
  private static func supportedClasses() async throws -> Set<String> {
    let host = WorkbenchTestHost(ClassProbe(), width: 300, height: 300)
    defer { host.window.close() }
    try await host.settle()
    let present = identifiers(in: host)
    return Set(ClassProbe.classes.filter { present.contains("probe \($0)") })
  }

  private func expectPresent<Content>(
    _ identifier: String, kind: String, supported: Set<String>, in host: WorkbenchTestHost<Content>,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    func check() async throws {
      let element = try await host.element(identifier)
      #expect(
        Self.identifier(of: element) == identifier, "\(identifier) matched by label or title only",
        sourceLocation: sourceLocation)
    }
    if supported.contains(kind) {
      try await check()
    } else {
      await withKnownIssue(
        "\(kind) identifiers are not exposed on this macOS", isIntermittent: true,
        sourceLocation: sourceLocation
      ) {
        try await check()
      }
    }
  }

  private static func text(_ element: AnyObject, _ attribute: String) -> String? {
    guard let object = element as? NSObject else { return nil }
    let selector = NSSelectorFromString(attribute)
    guard object.responds(to: selector), let value = object.perform(selector)?.takeUnretainedValue()
    else { return nil }
    return (value as? String) ?? (value as? NSAttributedString)?.string
  }

  private static func identifier(of element: AnyObject) -> String {
    element.accessibilityIdentifier?() ?? ""
  }

  private static func allElements<Content>(in host: WorkbenchTestHost<Content>) -> [AnyObject] {
    var seen = Set<ObjectIdentifier>()
    let everything: [AnyObject] = host.elements + host.hitElements + host.subviews
    return everything.filter { seen.insert(ObjectIdentifier($0)).inserted }
  }

  private static func owners<Content>(in host: WorkbenchTestHost<Content>) -> [String: [AnyObject]]
  {
    Dictionary(grouping: allElements(in: host), by: identifier)
  }

  private static func identifiers<Content>(in host: WorkbenchTestHost<Content>) -> Set<String> {
    Set(owners(in: host).keys)
  }
}

private struct RecreatedInspector: View {
  let model: WorkbenchModel
  let present: Bool

  var body: some View {
    if present {
      ComparisonInspector(model: model, state: model.inspector)
    } else {
      Color.clear
    }
  }
}

private struct ClassProbe: View {
  static let classes = ["TextField", "Button", "Toggle", "Picker", "Slider"]
  @State private var text = 1.0
  @State private var enabled = false
  @State private var choice = 0
  @State private var value = 0.5

  var body: some View {
    VStack {
      TextField("Probe", value: $text, format: .number).textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("probe TextField")
      Button("Probe", systemImage: "arrow.counterclockwise") {}.labelStyle(.iconOnly)
        .buttonStyle(.borderless).accessibilityIdentifier("probe Button")
      Toggle("Probe", isOn: $enabled).toggleStyle(.checkbox)
        .accessibilityIdentifier("probe Toggle")
      Picker("Probe", selection: $choice) {
        Text(verbatim: "One").tag(0)
        Text(verbatim: "Two").tag(1)
      }.labelsHidden().accessibilityIdentifier("probe Picker")
      Slider(value: $value).accessibilityIdentifier("probe Slider")
    }.padding()
  }
}
