import Testing

@testable import TypefaceCore

@Suite struct DifferenceTests {
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
    #expect(Differences.ranked(scores, shape: true, spacing: false).first?.glyph == "a")
    #expect(Differences.ranked(scores, shape: false, spacing: true).first?.glyph == "x")
    let order = Differences.ranked(scores, shape: true, spacing: true).map(\.glyph)
    #expect(order == ["x", "a", "@"])
    #expect(
      order == Differences.ranked(scores.reversed(), shape: false, spacing: false).map(\.glyph))
    let scaled = scores.map {
      GlyphDifference(glyph: $0.glyph, shape: $0.shape, spacing: $0.spacing * 1000)
    }
    #expect(order == Differences.ranked(scaled, shape: true, spacing: true).map(\.glyph))
    let zeros = [
      GlyphDifference(glyph: "b", shape: 0, spacing: 0), .init(glyph: "a", shape: 0, spacing: 0),
    ]
    #expect(Differences.ranked(zeros, shape: true, spacing: true).map(\.glyph) == ["a", "b"])
    #expect(Differences.highlights(zeros, text: "ab", shape: true, spacing: true).isEmpty)
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
      Differences.highlights(scores, text: sample, shape: true, spacing: false)
        == Set(Array("efghijkl").map(String.init)))
    #expect(
      Differences.highlights(scores, text: sample, shape: false, spacing: true)
        == Set(Array("abcdefgh").map(String.init)))
    #expect(
      Differences.highlights(scores, text: sample, shape: true, spacing: true) == Set(letters))
    #expect(Differences.highlights(scores, text: sample, shape: false, spacing: false).isEmpty)
    #expect(
      Differences.ranked(scores, shape: true, spacing: true)
        == Differences.ranked(scores, shape: false, spacing: false))
  }
}
