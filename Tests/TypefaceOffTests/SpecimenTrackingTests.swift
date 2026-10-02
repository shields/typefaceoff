import AppKit
import CoreText
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct SpecimenTrackingTests {
  @Test(arguments: [0.0, 0.025, -0.04], [0.0, 0.025, -0.04])
  func trackingUpdatesMatchFreshRenderingWithMissingGlyphs(before: Double, after: Double) {
    var config = FontConfiguration("HelveticaNeue")
    config.tracking = before
    config.features["aat.1.2"] = 2
    let text = "\tfi e\u{301} 🦄\r\n👩‍🚀 fl  "
    let original = SpecimenText.makeContent(config: config, text: text)
    let storage = NSMutableAttributedString(attributedString: original.text)
    config.tracking = after
    SpecimenText.updateTracking(config: config, storage: storage, range: original.bodyRange)
    let fresh = SpecimenText.makeContent(config: config, text: text)
    #expect(storage == fresh.text)
    #expect(original.spans == fresh.spans)
    #expect(original.bodyRange == fresh.bodyRange)
    #expect(original.bodyRange.location > 0)
    #expect(
      storage.attribute(
        NSAttributedString.Key(kCTTrackingAttributeName as String), at: 0, effectiveRange: nil)
        == nil)
  }

  @Test(arguments: ["Helvetica Neue", "Skia"])
  func trackingUpdatesPreserveEmphasisAndUnavailableItalic(name: String) throws {
    let face = try #require(FontCatalog().preferredFace(in: name))
    var config = FontConfiguration(face.id)
    let sample = Sample.reading
    let content = SpecimenText.makeContent(config: config, text: sample.text, sample: sample)
    let storage = NSMutableAttributedString(attributedString: content.text)
    for tracking in [0.04, -0.01, 0] {
      config.tracking = tracking
      SpecimenText.updateTracking(config: config, storage: storage, range: content.bodyRange)
      #expect(
        storage == SpecimenText.makeContent(config: config, text: sample.text, sample: sample).text)
    }
  }

  @Test(arguments: ["", "  \n", "a"])
  func emptyBodiesAndMissingFontsKeepTheirMessages(text: String) {
    for name in ["HelveticaNeue", "TypefaceOff-Does-Not-Exist"] {
      var config = FontConfiguration(name)
      let content = SpecimenText.makeContent(config: config, text: text)
      let storage = NSMutableAttributedString(attributedString: content.text)
      config.tracking = 0.04
      SpecimenText.updateTracking(config: config, storage: storage, range: content.bodyRange)
      #expect(storage == SpecimenText.makeContent(config: config, text: text).text)
    }
  }

  @Test func onlyTrackingChangesCanReuseRenderedContent() {
    let config = FontConfiguration("HelveticaNeue")
    let original = SpecimenText.RenderKey(config: config, text: "fi", sample: .custom)
    var changed = config
    changed.tracking = 0.03
    #expect(
      SpecimenText.RenderKey(config: changed, text: "fi", sample: .custom).changesOnlyTracking(
        from: original))
    #expect(!original.changesOnlyTracking(from: original))
    #expect(
      !SpecimenText.RenderKey(config: changed, text: "fl", sample: .custom).changesOnlyTracking(
        from: original))
    #expect(
      !SpecimenText.RenderKey(config: changed, text: "fi", sample: .reading).changesOnlyTracking(
        from: original))
    for alteration in 0..<4 {
      var structural = changed
      switch alteration {
      case 0: structural.size = 44
      case 1: structural.postScriptName = "ArialMT"
      case 2: structural.axes[0] = 1
      default: structural.features["ot.kern"] = 0
      }
      #expect(
        !SpecimenText.RenderKey(config: structural, text: "fi", sample: .custom)
          .changesOnlyTracking(from: original))
    }
  }

  @Test func trackingEditsPreserveSelectionAndAvoidCharacterEdits() async throws {
    let text = String(repeating: "fi a 🦄\n", count: 80)
    var config = FontConfiguration("HelveticaNeue")
    let host = WorkbenchTestHost(SpecimenText(config: config, text: text), width: 400, height: 250)
    defer { host.window.close() }
    try await host.settle()
    let specimen = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
    let storage = try #require(specimen.textStorage)
    let spans = specimen.spans
    let selected = try #require(spans.first { $0.glyph == "a" }).range
    specimen.setSelectedRange(selected)
    let counter = TrackingEditCounter()
    storage.delegate = counter
    for tracking in [0.03, -0.02, 0] {
      config.tracking = tracking
      host.setContent(SpecimenText(config: config, text: text, highlights: ["a"]))
      try await host.settle()
      #expect(specimen.textStorage === storage)
      #expect(storage == SpecimenText.makeContent(config: config, text: text).text)
      #expect(specimen.spans == spans)
      #expect(specimen.selectedRange() == selected)
    }
    #expect(counter.attributeEdits > 0)
    #expect(counter.characterEdits == 0)
  }
}

@MainActor private final class TrackingEditCounter: NSObject, @preconcurrency NSTextStorageDelegate
{
  var attributeEdits = 0
  var characterEdits = 0

  func textStorage(
    _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange, changeInLength delta: Int
  ) {
    if editedMask.contains(.editedAttributes) { attributeEdits += 1 }
    if editedMask.contains(.editedCharacters) { characterEdits += 1 }
  }
}
