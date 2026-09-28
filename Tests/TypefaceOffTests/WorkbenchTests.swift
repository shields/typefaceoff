import AppKit
import Combine
import CoreText
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct WorkbenchTests {
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

  @Test func featurePreviewsUseConfiguredShapingAndLabelUnavailableCharacters() {
    var config = FontConfiguration("HelveticaNeue")
    config.features["aat.1.2"] = 2
    let enabled = FontPreviewText.content(config: config, text: "fi")
    config.features["aat.1.2"] = 3
    let disabled = FontPreviewText.content(config: config, text: "fi")
    #expect(CTLineGetGlyphCount(CTLineCreateWithAttributedString(enabled)) == 1)
    #expect(CTLineGetGlyphCount(CTLineCreateWithAttributedString(disabled)) == 2)
    #expect(FontPreviewText.content(config: config, text: "🦄").string == "Unavailable")
    #expect(
      FontPreviewText.content(config: .init("TypefaceOff-Does-Not-Exist"), text: "a").string
        == "Unavailable")
  }

  @Test func specimenRunsKeepUTF16TargetsAroundMissingCharactersAndWhitespace() throws {
    let text = "\tfi e\u{301} 🦄\r\n👩‍🚀 fl  "
    let config = FontConfiguration("HelveticaNeue")
    let content = SpecimenText.makeContent(config: config, text: text)
    #expect(
      content.text.string
        == "2 unavailable characters\n\tfi e\u{301} [U+1F984]\r\n[U+1F469 U+200D U+1F680] fl  ")
    #expect(content.spans.map(\.glyph) == ["f", "i", "e\u{301}", "🦄", "👩‍🚀", "f", "l"])
    for span in content.spans {
      let rendered = content.text.attributedSubstring(from: span.range)
      if span.supported {
        #expect(rendered.string == span.glyph)
        #expect(rendered.attribute(.toolTip, at: 0, effectiveRange: nil) == nil)
        let font = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil)) as! CTFont
        #expect(CTFontCopyPostScriptName(font) as String == config.postScriptName)
      } else {
        #expect(rendered.string.hasPrefix("[U+"))
        #expect(
          rendered.attribute(.toolTip, at: 0, effectiveRange: nil) as? String
            == "Unavailable: \(unicodeDescription(span.glyph))")
      }
    }
    #expect(SpecimenText.makeContent(config: config, text: "").text.length == 0)
    #expect(SpecimenText.makeContent(config: config, text: "  \n").text.string == "  \n")
  }

  @Test(arguments: Sample.allCases, [14.0, 37.0])
  func specimensPreserveConfiguredTypographyAndNativeSpacing(sample: Sample, size: Double) {
    var config = FontConfiguration("HelveticaNeue-Italic")
    config.size = size
    config.tracking = 0.02
    config.features["aat.1.2"] = 2
    let text =
      sample == .custom
      ? "\nFirst line\nSecond line\n\n\nKeep *literal* punctuation.\r\nLast line\n" : sample.text
    let content = SpecimenText.makeContent(config: config, text: text, sample: sample)
    #expect(content.text.string == text)
    content.text.enumerateAttributes(in: NSRange(location: 0, length: content.text.length)) {
      attributes, _, _ in
      let font = attributes[.font] as! CTFont
      #expect(CTFontCopyPostScriptName(font) as String == config.postScriptName)
      #expect(abs(CTFontGetSize(font) - size) < 0.000001)
      #expect(
        attributes[NSAttributedString.Key(kCTTrackingAttributeName as String)] as? Double
          == config.tracking * size)
      #expect(attributes[.ligature] as? Int == 1)
      let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle ?? .default
      #expect(paragraph == .default)
    }
    for span in content.spans {
      #expect(span.supported)
      #expect(content.text.attributedSubstring(from: span.range).string == span.glyph)
    }
  }

  @Test func chapterEmphasisSurvivesParagraphLayoutAndKeepsCharacterTargets() throws {
    var config = FontConfiguration("HelveticaNeue")
    config.tracking = 0.025
    config.features["aat.1.2"] = 3
    let sample = Sample.reading
    let content = SpecimenText.makeContent(config: config, text: sample.text, sample: sample)
    #expect(content.text.string == sample.text)
    var emphasizedWords: [String] = []
    content.text.enumerateAttribute(.font, in: NSRange(location: 0, length: content.text.length)) {
      value, range, _ in
      let font = value as! CTFont
      #expect(abs(CTFontGetSize(font) - config.size) < 0.000001)
      if CTFontGetSymbolicTraits(font).contains(.traitItalic) {
        #expect(CTFontCopyPostScriptName(font) as String == "HelveticaNeue-Italic")
        emphasizedWords.append(content.text.attributedSubstring(from: range).string)
        #expect(
          content.text.attribute(
            NSAttributedString.Key(kCTTrackingAttributeName as String), at: range.location,
            effectiveRange: nil) as? Double == config.tracking * config.size)
        #expect(
          content.text.attribute(.ligature, at: range.location, effectiveRange: nil) as? Int == 0)
      }
    }
    #expect(
      emphasizedWords == sample.italicRanges.map { (sample.text as NSString).substring(with: $0) })
    for span in content.spans {
      #expect(span.supported)
      #expect(content.text.attributedSubstring(from: span.range).string == span.glyph)
    }
    let plain = SpecimenText.makeContent(config: config, text: "Keep *literal* punctuation.")
    #expect(plain.text.string == "Keep *literal* punctuation.")
  }

  @Test func unavailableItalicIsVisibleWithoutSubstitutingAnotherFamily() throws {
    let sample = Sample.reading
    let skia = try #require(FontCatalog().preferredFace(in: "Skia"))
    let content = SpecimenText.makeContent(
      config: .init(skia.id), text: sample.text, sample: sample)
    #expect(content.text.string.contains("Italic unavailable: Skia\n"))
    let range = (content.text.string as NSString).range(of: "is grand!")
    try #require(range.location != NSNotFound)
    let font = content.text.attribute(.font, at: range.location, effectiveRange: nil) as! CTFont
    #expect(CTFontCopyFamilyName(font) as String == "Skia")
    #expect(
      content.text.attribute(.toolTip, at: range.location, effectiveRange: nil) as? String
        == "Italic unavailable: Skia")
  }

  @Test func sliderGestureHasOneUndoAcrossManyUpdates() {
    let model = WorkbenchModel()
    let undo = UndoManager()
    undo.groupsByEvent = false
    let initial = model.comparison
    model.beginContinuousEdit("Resize")
    for size in [25.0, 30.0, 44.0] {
      model.edit("Resize", undoManager: undo) {
        $0.set(.size, to: size, side: .a, catalog: model.catalog)
      }
    }
    #expect(!undo.canUndo)
    undo.beginUndoGrouping()
    model.endContinuousEdit(undoManager: undo)
    undo.endUndoGrouping()
    undo.undo()
    #expect(model.comparison == initial)
    #expect(!undo.canUndo)
    undo.redo()
    #expect(model.comparison.a.size == 44)
    #expect(model.comparison.b?.size == 44)
  }
  @Test func linkedEditsPublishAndUndoAsOneChange() {
    let model = WorkbenchModel()
    let undo = UndoManager()
    undo.groupsByEvent = false
    var published = 0
    let observation = model.objectWillChange.sink { published += 1 }
    let original = model.comparison
    undo.beginUndoGrouping()
    model.edit("Resize", undoManager: undo) {
      $0.set(.size, to: 44, side: .a, catalog: model.catalog)
    }
    undo.endUndoGrouping()
    #expect(published == 1)
    #expect(model.comparison.a.size == 44)
    #expect(model.comparison.b?.size == 44)
    undo.undo()
    #expect(model.comparison == original)
    undo.redo()
    #expect(model.comparison.a.size == 44)
    #expect(model.comparison.b?.size == 44)
    withExtendedLifetime(observation) {}
  }

  @Test func browsingDoesNotConsumeUndoOrRedoAndKeepsTheCurrentInspection() {
    let model = WorkbenchModel()
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    model.edit("Resize", undoManager: undo) {
      $0.set(.size, to: 44, side: .a, catalog: model.catalog)
    }
    undo.endUndoGrouping()
    for glyph in ["a", "g", "@"] {
      model.updatePresentation {
        $0.mode = .glyph
        $0.selectedGlyph = glyph
        $0.shape = false
        $0.spacing = true
        $0.frequency = false
      }
    }
    undo.undo()
    #expect(model.comparison.a.size == 22)
    #expect(model.comparison.b?.size == 22)
    #expect(!undo.canUndo)
    #expect(model.comparison.mode == .glyph)
    #expect(model.comparison.selectedGlyph == "@")
    #expect(!model.comparison.shape && model.comparison.spacing)
    #expect(!model.comparison.frequency)
    model.updatePresentation { $0.selectedGlyph = "g" }
    #expect(undo.canRedo)
    undo.redo()
    #expect(model.comparison.a.size == 44)
    #expect(model.comparison.b?.size == 44)
    #expect(model.comparison.selectedGlyph == "g")
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
