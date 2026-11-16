import Testing

@testable import TypefaceCore

@Suite struct DifferenceTests {
  @Test func displayedScoresUseTheExactRankingMetric() {
    let scores = [
      GlyphDifference(glyph: "a", shape: 0.8, spacing: 0.01),
      .init(glyph: "@", shape: 0.2, spacing: 0.06), .init(glyph: "x", shape: 0.7, spacing: 0.07),
    ]
    for shape in [false, true] {
      for spacing in [false, true] {
        for frequency in [false, true] {
          let ranked = Differences.scored(
            scores, shape: shape, spacing: spacing, frequency: frequency)
          #expect(
            ranked.map(\.difference)
              == Differences.ranked(scores, shape: shape, spacing: spacing, frequency: frequency))
          #expect(ranked.map(\.weighted) == ranked.map(\.weighted).sorted(by: >))
          for item in ranked {
            #expect(item.id == item.difference.id)
            #expect(item.weighted == item.measured * (frequency ? item.difference.weight : 1))
            if shape != spacing {
              #expect(item.measured == (shape ? item.difference.shape : item.difference.spacing))
            }
          }
        }
      }
    }
    let combined = Differences.scored(scores, shape: true, spacing: true, frequency: false)
    #expect(combined.map(\.measured) == [1.5, 1, 0.5])
  }
  @Test func antialiasedIntersectionOverUnion() {
    #expect(Differences.inkDifference([0, 0], [0, 0]) == 0)
    #expect(Differences.inkDifference([255, 127], [255, 127]) == 0)
    #expect(Differences.inkDifference([255, 0], [0, 255]) == 1)
    let expected = 1 - 255.0 / (255 + 128 + 64)
    #expect(Differences.inkDifference([255, 128, 0], [255, 0, 64]) == expected)
  }

  @Test func rankingsRespectIndependentMetricsAndTies() {
    let scores = [
      GlyphDifference(glyph: "a", shape: 0.8, spacing: 0.01),
      .init(glyph: "@", shape: 0.2, spacing: 0.06), .init(glyph: "x", shape: 0.7, spacing: 0.07),
    ]
    #expect(
      Differences.ranked(scores, shape: true, spacing: false, frequency: false).first?.glyph
        == "a")
    #expect(
      Differences.ranked(scores, shape: false, spacing: true, frequency: false).first?.glyph
        == "x")
    let order = Differences.ranked(scores, shape: true, spacing: true, frequency: false).map(
      \.glyph)
    #expect(order == ["x", "a", "@"])
    #expect(
      order
        == Differences.ranked(scores.reversed(), shape: false, spacing: false, frequency: false)
        .map(\.glyph))
    let scaled = scores.map {
      GlyphDifference(glyph: $0.glyph, shape: $0.shape, spacing: $0.spacing * 1000)
    }
    #expect(
      order
        == Differences.ranked(scaled, shape: true, spacing: true, frequency: false).map(
          \.glyph))
    let zeros = [
      GlyphDifference(glyph: "b", shape: 0, spacing: 0), .init(glyph: "a", shape: 0, spacing: 0),
    ]
    #expect(
      Differences.ranked(zeros, shape: true, spacing: true, frequency: false).map(\.glyph)
        == ["a", "b"])
    #expect(
      Differences.highlights(zeros, text: "ab", shape: true, spacing: true, frequency: false)
        .isEmpty)
  }

  @Test func zeroDifferencesNeverOutrankPositiveOnesWhenWeighted() {
    let scores = [
      GlyphDifference(glyph: "@", shape: 0, spacing: 0),
      GlyphDifference(glyph: "e", shape: 0.02, spacing: 0.01),
    ]
    for shape in [true, false] {
      for spacing in [true, false] {
        #expect(
          Differences.ranked(scores, shape: shape, spacing: spacing, frequency: true).first?
            .glyph == "e")
      }
    }
    #expect(
      Differences.highlights(scores, text: "@e", shape: true, spacing: true, frequency: true)
        == ["e"])
  }

  @Test func frequencyWeightingCanRankACommonLetterAboveALargerRawDifference() {
    let scores = [
      GlyphDifference(glyph: "e", shape: 0.5, spacing: 0),
      GlyphDifference(glyph: "@", shape: 0.9, spacing: 0),
    ]
    #expect(
      Differences.ranked(scores, shape: true, spacing: false, frequency: false).first?.glyph
        == "@")
    #expect(
      Differences.ranked(scores, shape: true, spacing: false, frequency: true).first?.glyph
        == "e")
  }

  @Test func combinedWeightedRankingMatchesPercentileSumTimesWeight() {
    // Distinct percentile sums, and weights (full, partial, floor) that survive
    // regenerating the table.
    let scores = [
      GlyphDifference(glyph: "e", shape: 0.1, spacing: 0.4),
      GlyphDifference(glyph: "@", shape: 0.4, spacing: 0.95),
      GlyphDifference(glyph: "#", shape: 0.7, spacing: 0.1),
      GlyphDifference(glyph: "\u{E000}", shape: 0.95, spacing: 0.7),
    ]
    let percentileSum: [String: Double] = [
      "e": 1.0 / 3, "@": 4.0 / 3, "#": 2.0 / 3, "\u{E000}": 5.0 / 3,
    ]
    let byGlyph = Dictionary(uniqueKeysWithValues: scores.map { ($0.glyph, $0) })
    func expectedOrder(weighted: Bool) -> [String] {
      percentileSum.keys.sorted {
        let left = percentileSum[$0]! * (weighted ? byGlyph[$0]!.weight : 1)
        let right = percentileSum[$1]! * (weighted ? byGlyph[$1]!.weight : 1)
        return left == right ? $0 < $1 : left > right
      }
    }
    #expect(
      Differences.ranked(scores, shape: true, spacing: true, frequency: true).map(\.glyph)
        == expectedOrder(weighted: true))
    #expect(
      Differences.ranked(scores, shape: true, spacing: true, frequency: false).map(\.glyph)
        == expectedOrder(weighted: false))
  }

  @Test func weightedHighlightsRankByRawTimesWeightAmongPresentGlyphs() {
    let rare = (0..<8).map { index in
      (glyph: String(UnicodeScalar(0xE000 + index)!), shape: 0.6 + Double(index) * 0.05)
    }
    let scores =
      [GlyphDifference(glyph: "e", shape: 0.5, spacing: 0)]
      + rare.map { GlyphDifference(glyph: $0.glyph, shape: $0.shape, spacing: 0) }
    let text = "e" + rare.map(\.glyph).joined()
    let unweighted = Differences.highlights(
      scores, text: text, shape: true, spacing: false, frequency: false)
    #expect(unweighted.count == 8)
    #expect(!unweighted.contains("e"))
    let weighted = Differences.highlights(
      scores, text: text, shape: true, spacing: false, frequency: true)
    #expect(weighted.count == 8)
    #expect(weighted.contains("e"))
    #expect(!weighted.contains(rare[0].glyph))
  }

  @Test func rankingWorkerHandlesIdenticalFontsAndCancellation() async throws {
    let engine = DifferenceEngine()
    let config = FontConfiguration("HelveticaNeue")
    let scores = try await engine.scores(a: config, b: config, sample: "")
    #expect(scores.count == 94)
    #expect(scores.allSatisfy { $0.shape == 0 && $0.spacing == 0 })
    let task = Task {
      try await engine.scores(a: config, b: .init("ArialMT"), sample: Sample.reading.text)
    }
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("Expected cancellation")
    } catch is CancellationError {} catch { Issue.record(error) }
  }

  @Test func allHighlightCombinationsSelectOnlyTheTopEightPresentPositiveScores() {
    let letters = Array("abcdefghijkl").map(String.init)
    let scores =
      letters.enumerated().map {
        GlyphDifference(
          glyph: $0.element, shape: Double($0.offset + 1) / 12,
          spacing: Double(12 - $0.offset) / 100)
      } + [.init(glyph: "@", shape: 1, spacing: 1), .init(glyph: "z", shape: 0, spacing: 0)]
    let sample = letters.joined() + "z"
    #expect(
      Differences.highlights(scores, text: sample, shape: true, spacing: false, frequency: false)
        == Set(Array("efghijkl").map(String.init)))
    #expect(
      Differences.highlights(scores, text: sample, shape: false, spacing: true, frequency: false)
        == Set(Array("abcdefgh").map(String.init)))
    #expect(
      Differences.highlights(scores, text: sample, shape: true, spacing: true, frequency: false)
        == Set(letters))
    #expect(
      Differences.highlights(scores, text: sample, shape: false, spacing: false, frequency: false)
        .isEmpty)
    #expect(
      Differences.ranked(scores, shape: true, spacing: true, frequency: false)
        == Differences.ranked(scores, shape: false, spacing: false, frequency: false))
  }

  @Test func canonicallyEquivalentCharactersRankSeparately() {
    let candidates = Differences.candidates(sample: "\u{37E}")
    #expect(candidates.filter { $0 == ";" }.map(\.unicodeScalars.first) == [";", "\u{37E}"])
    let scores = [
      GlyphDifference(glyph: ";", shape: 0.1, spacing: 0.01),
      .init(glyph: "\u{37E}", shape: 0.9, spacing: 0.09),
    ]
    let ranked = Differences.ranked(scores, shape: true, spacing: true, frequency: false)
    #expect(ranked.map(\.id) == [["\u{37E}"], [";"]])
  }

  @Test func highlightsDoNotTreatACanonicalEquivalentAsPresent() {
    let scores = [
      GlyphDifference(glyph: ";", shape: 0.5, spacing: 0),
      GlyphDifference(glyph: "\u{37E}", shape: 0, spacing: 0),
    ]
    let highlighted = Differences.highlights(
      scores, text: "\u{37E}", shape: true, spacing: false, frequency: false)
    #expect(highlighted.isEmpty)
  }
}
