import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

/// The fuzzer records these names and finds controls by them, so they are a contract.
@Suite(.serialized) @MainActor struct AccessibilityIdentifierTests {
  private static let inspectorIdentifiers = [
    ("Font A Reset appearance", "Button"), ("Font A Appearance lock", "Button"),
    ("Font A Reset size", "Button"), ("Font A Size field", "TextField"),
    ("Font A Reset tracking", "Button"), ("Font A Tracking field", "TextField"),
    ("Font A Reset typography", "Button"), ("Font A Size", "Slider"),
    ("Font A style", "Picker"),
    ("Font A Reset leading", "Button"), ("Font A Leading field", "TextField"),
    ("Font A Leading", "Slider"), ("Font A Auto leading", "Toggle"),
  ]

  @Test func sideNamesPrefixEveryPerInspectorIdentifier() {
    #expect(Side.a.fontName == "Font A")
    #expect(Side.b.fontName == "Font B")
  }

  @Test func inspectorControlsCarryStableIdentifiers() async throws {
    let supported = try await Self.supportedClasses()
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 246, height: 900)
    defer { host.window.close() }
    try await host.settle()
    for (identifier, kind) in Self.inspectorIdentifiers {
      try await expectPresent(identifier, kind: kind, supported: supported, in: host)
    }
    let axis = try #require(model.comparison.a.face.axes.first)
    for identifier in ["Font A \(axis.name) field", "Font A Reset \(axis.name.lowercased())"] {
      let kind = identifier.hasSuffix("field") ? "TextField" : "Button"
      try await expectPresent(identifier, kind: kind, supported: supported, in: host)
    }
  }

  @Test func typographyControlsCarryStableIdentifiers() async throws {
    let supported = try await Self.supportedClasses()
    let model = WorkbenchModel(comparison: Comparison(a: .init("ArialMT")))
    let host = WorkbenchTestHost(FontInspector(model: model, side: .a), width: 246, height: 900)
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

  @Test func bothInspectorsCarryTheirOwnIdentifiers() async throws {
    let supported = try await Self.supportedClasses()
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await host.settle()
    for side in ["A", "B"] {
      for (identifier, kind) in [
        ("Font \(side) Reset appearance", "Button"), ("Font \(side) Size field", "TextField"),
        ("Font \(side) Tracking field", "TextField"), ("Font \(side) Size", "Slider"),
        ("Font \(side) Leading field", "TextField"), ("Font \(side) Reset leading", "Button"),
        ("Font \(side) Auto leading", "Toggle"),
      ] {
        try await expectPresent(identifier, kind: kind, supported: supported, in: host)
      }
    }
  }

  @Test func identifiersAreUniquePerElement() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    try await Self.waitForRankedStrip(in: host)
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
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel(comparison: comparison)))
    defer { host.window.close() }
    try await Self.waitForRankedStrip(in: host)
    let elements = Self.allElements(in: host)
    var reserved = Set(["Font A inspector", "Font B inspector"])
    func collect(_ menu: NSMenu?) {
      for item in menu?.items ?? [] {
        reserved.insert(item.title)
        collect(item.submenu)
      }
    }
    collect(NSApp.mainMenu)
    let identifiers = Set(elements.map(Self.identifier).filter { !$0.isEmpty })
    for element in elements {
      let own = Self.identifier(of: element)
      for text in [
        element.accessibilityLabel?(), element.accessibilityTitle?(),
      ].compactMap({ $0 }) where text != own && identifiers.contains(text) {
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
      width: 900, height: 900)
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Language missing base disclosure")
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
      for label in [element.accessibilityLabel?(), element.accessibilityTitle?()].compactMap({ $0 })
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
    let expected = [
      "Font A inspector scroll area", "Font B inspector scroll area",
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
    let host = WorkbenchTestHost(MatchSheet(model: WorkbenchModel()))
    defer { host.window.close() }
    try await host.settle()
    let scrolls = host.subviews.compactMap { $0 as? NSScrollView }.map {
      $0.accessibilityIdentifier()
    }
    #expect(scrolls.contains("Reference A specimen scroll area"))
    #expect(scrolls.contains("Proposed B specimen scroll area"))
    let texts = host.subviews.compactMap { $0 as? SpecimenNSTextView }
    #expect(
      texts.map { $0.accessibilityIdentifier() }.sorted() == [
        "Proposed B specimen", "Reference A specimen",
      ])
    #expect(texts.allSatisfy { $0.accessibilityLabel() == "Font A specimen" })
  }

  @Test func legacyNamesStillResolve() async throws {
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel()))
    defer { host.window.close() }
    try await host.settle()
    for label in [
      "Reset appearance", "Unlock appearance", "Reset size", "Reset tracking",
      "Reset typography", "Kerning", "Common", "Font A family",
      "Swap fonts",
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
    #expect(names() == ["Font A inspector scroll area"])
    host.setContent(RecreatedInspector(model: model, present: false))
    try await host.settle { names().isEmpty }
    host.setContent(RecreatedInspector(model: model, present: true))
    try await host.settle { names() == ["Font A inspector scroll area"] }
  }

  @Test func collapsedInspectorKeepsItsScrollAreaName() async throws {
    let host = WorkbenchTestHost(WorkbenchView(model: WorkbenchModel()))
    defer { host.window.close() }
    try await host.settle()
    try await host.press("Toggle font A inspector")
    try await host.settle()
    let names = host.subviews.compactMap { ($0 as? NSScrollView)?.accessibilityIdentifier() }
    #expect(names.contains("Font A inspector scroll area"))
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

  private static func waitForRankedStrip<Content>(in host: WorkbenchTestHost<Content>) async throws
  {
    try await host.settle {
      allElements(in: host).contains { ($0.accessibilityLabel?() ?? "").hasPrefix("Inspect U+") }
    }
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
      FontInspector(model: model, side: .a)
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
