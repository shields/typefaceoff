import AppKit
import Combine
import CoreText
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct DocumentTests {
  @Test(arguments: ["en_US", "de_DE", "fr_FR"])
  func sharedSizeUsesTheDisplayLocale(identifier: String) throws {
    let locale = Locale(identifier: identifier)
    let text = SharedSizeFormat.style(locale: locale).format(22.5)
    #expect(text == (identifier == "en_US" ? "22.5" : "22,5"))
    #expect(SharedSizeFormat.parse(text, locale: locale) == 22.5)
    #expect(SharedSizeFormat.parse("44", locale: locale) == 44)
    #expect(SharedSizeFormat.parse("invalid", locale: locale) == nil)
    #expect(SharedSizeFormat.parse("22garbage", locale: locale) == nil)
    #expect(SharedSizeFormat.parse("NaN", locale: locale) == nil)
    #expect(SharedSizeFormat.parse("∞", locale: locale) == nil)
  }

  @Test func interactiveSpecimenPreservesLigaturesAndMissingCharacterIdentity() {
    let config = FontConfiguration("HelveticaNeue")
    let sample = SpecimenText.makeContent(config: config, text: "fi")
    #expect(CTLineGetGlyphCount(CTLineCreateWithAttributedString(sample.text)) == 1)
    #expect(sample.spans.map(\.glyph) == ["f", "i"])
    let missing = SpecimenText.makeContent(config: config, text: "🦄")
    #expect(missing.text.string == "1 unavailable character\n[U+1F984]")
    #expect(missing.spans.first?.glyph == "🦄")
    #expect(missing.spans.first?.supported == false)
  }

  @Test func unavailableLabelsCountDistinctGraphemesAndKeepEveryScalarAndClickTarget() throws {
    let content = SpecimenText.makeContent(config: .init("HelveticaNeue"), text: "A🦄🦄👩‍🚀")
    #expect(content.text.string.hasPrefix("2 unavailable characters\nA"))
    #expect(content.spans.map(\.glyph) == ["A", "🦄", "🦄", "👩‍🚀"])
    let astronaut = try #require(content.spans.last)
    #expect(
      content.text.attributedSubstring(from: astronaut.range).string == "[U+1F469 U+200D U+1F680]")
    #expect(!astronaut.supported)
    let label = try #require(
      content.text.attribute(.toolTip, at: astronaut.range.location, effectiveRange: nil) as? String
    )
    #expect(
      label.contains("WOMAN") && label.contains("ZERO WIDTH JOINER") && label.contains("ROCKET"))
    let missingFont = SpecimenText.makeContent(
      config: .init("TypefaceOff-Does-Not-Exist"), text: "A")
    #expect(missingFont.text.string.hasPrefix("Font unavailable: TypefaceOff-Does-Not-Exist"))
    #expect(missingFont.spans.isEmpty)
  }

  @Test func specimenHierarchyPreservesConfiguredFontsAndCharacterTargets() throws {
    var config = FontConfiguration("HelveticaNeue-Italic")
    config.tracking = 0.02
    config.features["aat.1.2"] = 2
    let content = SpecimenText.makeContent(
      config: config, text: Sample.reading.text, sample: .reading)
    let heading = content.text.attribute(.font, at: 0, effectiveRange: nil) as! CTFont
    let bodyIndex = (content.text.string as NSString).range(of: "Alice was").location
    let body = content.text.attribute(.font, at: bodyIndex, effectiveRange: nil) as! CTFont
    let footerRange = try #require(content.footerRange)
    let footer =
      content.text.attribute(.font, at: footerRange.location, effectiveRange: nil) as! CTFont
    #expect(CTFontGetSize(heading) > CTFontGetSize(body))
    #expect(CTFontGetSize(footer) < CTFontGetSize(body))
    for font in [heading, body, footer] {
      #expect(CTFontCopyPostScriptName(font) as String == config.postScriptName)
    }
    for span in content.spans where span.supported {
      #expect(content.text.attributedSubstring(from: span.range).string == span.glyph)
    }
    let custom = SpecimenText.makeContent(config: config, text: Sample.reading.text)
    #expect(custom.footerRange == nil)
    let customFont = custom.text.attribute(.font, at: 0, effectiveRange: nil) as! CTFont
    #expect(abs(CTFontGetSize(customFont) - config.size) < 0.000001)
  }
  @Test func sliderGestureHasOneUndoAcrossManyUpdates() {
    let document = WorkbenchDocument()
    let undo = UndoManager()
    undo.groupsByEvent = false
    let initial = document.comparison
    document.beginContinuousEdit("Resize")
    for size in [25.0, 30.0, 44.0] {
      document.edit("Resize", undoManager: undo) {
        $0.set(.size, to: size, side: .a, catalog: document.catalog)
      }
    }
    #expect(!undo.canUndo)
    undo.beginUndoGrouping()
    document.endContinuousEdit(undoManager: undo)
    undo.endUndoGrouping()
    undo.undo()
    #expect(document.comparison == initial)
    #expect(!undo.canUndo)
    undo.redo()
    #expect(document.comparison.a.size == 44)
    #expect(document.comparison.b?.size == 44)
  }
  @Test func linkedEditsPublishAndUndoAsOneChange() {
    let document = WorkbenchDocument()
    let undo = UndoManager()
    undo.groupsByEvent = false
    var published = 0
    let observation = document.objectWillChange.sink { published += 1 }
    let original = document.comparison
    undo.beginUndoGrouping()
    document.edit("Resize", undoManager: undo) {
      $0.set(.size, to: 44, side: .a, catalog: document.catalog)
    }
    undo.endUndoGrouping()
    #expect(published == 1)
    #expect(document.comparison.a.size == 44)
    #expect(document.comparison.b?.size == 44)
    undo.undo()
    #expect(document.comparison == original)
    undo.redo()
    #expect(document.comparison.a.size == 44)
    #expect(document.comparison.b?.size == 44)
    withExtendedLifetime(observation) {}
  }

  @Test func snapshotsStayStableWhileEditing() throws {
    let document = WorkbenchDocument()
    let snapshot = try document.snapshot(contentType: .typefaceComparison)
    document.edit("Edit sample", undoManager: nil) { $0.customText = "changed" }
    #expect(snapshot.customText.isEmpty)
    #expect(try TypefaceCore.Comparison.decode(snapshot.encoded()) == snapshot)
  }

  @Test func browsingDoesNotConsumeUndoOrRedoAndKeepsTheCurrentInspection() {
    let document = WorkbenchDocument()
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    document.edit("Resize", undoManager: undo) {
      $0.set(.size, to: 44, side: .a, catalog: document.catalog)
    }
    undo.endUndoGrouping()
    for glyph in ["a", "g", "@"] {
      document.updatePresentation {
        $0.mode = .glyph
        $0.selectedGlyph = glyph
        $0.shape = false
        $0.spacing = true
      }
    }
    undo.undo()
    #expect(document.comparison.a.size == 22)
    #expect(document.comparison.b?.size == 22)
    #expect(!undo.canUndo)
    #expect(document.comparison.mode == .glyph)
    #expect(document.comparison.selectedGlyph == "@")
    #expect(!document.comparison.shape && document.comparison.spacing)
    document.updatePresentation { $0.selectedGlyph = "g" }
    #expect(undo.canRedo)
    undo.redo()
    #expect(document.comparison.a.size == 44)
    #expect(document.comparison.b?.size == 44)
    #expect(document.comparison.selectedGlyph == "g")
  }

  @Test func removingBWhileRankingClearsResults() async {
    let ranking = RankingModel()
    await ranking.update(Comparison())
    #expect(!ranking.scores.isEmpty)
    await ranking.update(Comparison(b: nil))
    #expect(ranking.scores.isEmpty)
    #expect(!ranking.comparing)
  }
}
