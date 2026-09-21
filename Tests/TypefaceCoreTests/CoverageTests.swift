import CoreText
import Foundation
import Testing

@testable import TypefaceCore

@Suite struct CoverageTests {
  @Test func matchingPreviewOptionsEqualTheCorrespondingProposals() throws {
    let catalog = FontCatalog()
    let comparison = Comparison()
    var options = MatchOptions()
    options.weight = false
    let preview = try #require(Matching.preview(comparison, options: options, catalog: catalog))
    #expect(preview.proposed == comparison.b)
    for (key, candidate) in [
      (\MatchOptions.weight, preview.weight), (\.xHeight, preview.xHeight),
      (\.tracking, preview.tracking),
    ] {
      var enabled = options
      enabled[keyPath: key] = true
      #expect(candidate == Matching.proposal(comparison, options: enabled, catalog: catalog))
    }
    #expect(Matching.preview(Comparison(b: nil), options: options, catalog: catalog) == nil)
    #expect(
      Matching.preview(
        Comparison(a: .init("TypefaceOff-Does-Not-Exist")), options: options, catalog: catalog)
        == nil)
  }
  @Test func samplesKeepTheirNamesAndText() {
    let expected: [(Sample, String, String)] = [
      (.reading, "Queen Alice", "“I’ll shake you into a kitten, that I will!”"),
      (.alphabet, "Alphabet", "The quick brown fox jumps over the lazy dog."),
      (.numerals, "Numerals & punctuation", "0,000.00"),
      (.custom, "Custom text", ""),
    ]
    for (sample, title, ending) in expected {
      var comparison = Comparison()
      comparison.sample = sample
      comparison.customText = "User-provided sample"
      #expect(sample.title == title)
      #expect(sample.text.hasSuffix(ending))
      #expect(comparison.text == (sample == .custom ? comparison.customText : sample.text))
    }
    #expect(Sample.custom.text.isEmpty)
    #expect(unicodeDescription("\u{1}") == "U+0001 UNNAMED CHARACTER")
  }

  @Test func queenAliceKeepsTheCompleteChapterAndSourceEmphasis() {
    let sample = Sample.reading
    #expect(Sample.allCases == [.reading, .alphabet, .numerals, .custom])
    #expect(sample.text.hasPrefix("“Well, this is grand!”"))
    #expect(sample.text.contains("Un-dish-cover the fish, or dishcover the riddle?”"))
    #expect(sample.text.hasSuffix("“I’ll shake you into a kitten, that I will!”"))
    #expect(
      sample.text.contains("Till the feast’s ready, we’ve time for a nap:\nWhen the feast’s over"))
    let emphasized = sample.italicRanges.map { (sample.text as NSString).substring(with: $0) }
    #expect(emphasized.count == 45)
    #expect(emphasized.first == "is")
    #expect(Array(emphasized.suffix(3)) == ["you", "now", "you"])
    #expect(!sample.text.contains("*"))
    for plain in [Sample.alphabet, .numerals, .custom] {
      #expect(plain.italicRanges.isEmpty)
    }
  }

  @Test func linkedAxesPreserveTheirOffsetsInBothDirections() throws {
    let catalog = FontCatalog()
    let face = try #require(catalog.preferredFace(in: "Skia"))
    let width = try #require(face.axes.first { $0.tag == "wdth" })
    var a = FontConfiguration(face.id)
    var b = a
    a.axes[width.id] = 0.8
    b.axes[width.id] = 1.0
    var comparison = Comparison(a: a, b: b)
    comparison.set(.axis(width.id), to: 0.9, side: .a, catalog: catalog)
    #expect(abs((comparison.b?.axes[width.id] ?? 0) - 1.1) < 0.00001)
    comparison.set(.axis(width.id), to: 1.0, side: .b, catalog: catalog)
    #expect(abs((comparison.a.axes[width.id] ?? 0) - 0.8) < 0.00001)
    comparison.link?.axisOffsets = [:]
    comparison.set(.axis(width.id), to: 1.0, side: .a, catalog: catalog)
    #expect(comparison.b?.axes[width.id] == 1.0)
    comparison.set(.axis(tagNumber("NONE")), to: 2, side: .a, catalog: catalog)
    #expect(comparison.a.axes[tagNumber("NONE")] == nil)
  }

  @Test func replacingFacesFiltersFeaturesAndClampsAxes() throws {
    let catalog = FontCatalog()
    let face = try #require(catalog.preferredFace(in: "Skia"))
    var config = FontConfiguration("HelveticaNeue")
    config.replaceFace(face)
    #expect(
      config.axes == Dictionary(uniqueKeysWithValues: face.axes.map { ($0.id, $0.defaultValue) }))
    config.features = ["ot.kern": 0, "nonexistent": 1]
    config.axes = Dictionary(uniqueKeysWithValues: face.axes.map { ($0.id, .infinity) })
    config.replaceFace(face)
    #expect(config.features == ["ot.kern": 0])
    for axis in face.axes { #expect(config.axes[axis.id] == axis.maximum) }
    let previous = config
    config.set(.size, to: .nan, catalog: catalog)
    #expect(config == previous)
    var comparison = Comparison(a: config, b: nil)
    comparison[.a] = nil
    #expect(comparison.a == config)
    comparison.set(.size, to: 33, side: .b, catalog: catalog)
    comparison.selectFamily(nil, side: .a, catalog: catalog)
    comparison.swap()
    #expect(comparison.a == config && comparison.b == nil)
    comparison.selectFamily("Arial", side: .b, catalog: catalog)
    #expect(comparison.b?.face.family == "Arial")
    #expect(comparison.b?.size == config.size)
    comparison.selectFace(face, side: .a, catalog: catalog)
    #expect(comparison.a.axes == FontConfiguration(face.id).axes)
  }

  @Test func featureGroupsAndExclusivePartnersReflectTheFontMetadata() {
    let groups: [(String, FontFeature.Group)] = [
      ("ot.cv01", .characterVariants), ("ot.ss01", .stylisticSets), ("ot.tnum", .numbers),
      ("ot.mark", .automatic), ("ot.kern", .common), ("invalid", .common),
      ("aat.35", .stylisticSets), ("aat.17", .characterVariants), ("aat.6", .numbers),
      ("aat.1.2", .common),
    ]
    for (id, group) in groups {
      let feature = FontFeature(id: id, name: id, options: [], defaultValue: 0)
      #expect(feature.group == group)
    }
    let tnum = FontFeature(id: "ot.tnum", name: "Tabular numerals", options: [], defaultValue: 0)
    var comparison = Comparison()
    comparison.setFeature(tnum, value: 1, side: .a)
    #expect(comparison.a.features["ot.tnum"] == 1)
    #expect(comparison.a.features["ot.pnum"] == 0)
    #expect(comparison.b?.features.isEmpty == true)
  }

  @Test func matchingOptionsCanBeDisabledIndependently() {
    var options = MatchOptions()
    #expect(!options.isEmpty)
    options.weight = false
    #expect(options.isEmpty)
    options.xHeight = true
    #expect(!options.isEmpty)
    options.xHeight = false
    options.tracking = true
    #expect(!options.isEmpty)
    var config = FontConfiguration("ArialMT")
    config.features["ot.kern"] = 0
    let attributes = FontRenderer.attributes(config)
    #expect(attributes[NSAttributedString.Key(kCTKernAttributeName as String)] as? Int == 0)
    config.tracking = 0.1
    #expect(
      FontRenderer.attributes(config)[NSAttributedString.Key(kCTTrackingAttributeName as String)]
        as? Double == 2.2)
  }

  @Test func highlightsAreLimitedToNonzeroCharactersInTheSample() {
    let scores = (0..<12).map { GlyphDifference(glyph: String($0), shape: Double($0), spacing: 0) }
    #expect(
      Differences.highlights(scores, text: "0123456789", shape: true, spacing: false)
        == Set((2...9).map(String.init)))
    #expect(Differences.highlights(scores, text: "0123456789", shape: false, spacing: true).isEmpty)
    #expect(Differences.ranked([], shape: true, spacing: true).isEmpty)
    #expect(scores[3].id == "3")
  }

  @Test func rankingCacheReturnsEquivalentResultsAfterEviction() async throws {
    let engine = DifferenceEngine()
    let config = FontConfiguration("ArialMT")
    let initial = try await engine.scores(a: config, b: config, sample: "")
    #expect(try await engine.scores(a: config, b: config, sample: "") == initial)
    for index in 1...9 {
      var next = config
      next.tracking = Double(index) / 100
      let result = try await engine.scores(a: config, b: next, sample: "🦄")
      #expect(!result.contains { $0.glyph == "🦄" })
      #expect(result.allSatisfy { $0.spacing > 0 })
    }
    #expect(try await engine.scores(a: config, b: config, sample: "") == initial)
  }
}
