import Testing

@testable import TypefaceCore

@Suite struct DifferenceInputTests {
  private struct Variant {
    let name: String
    let comparison: Comparison
    let sameInput: Bool
    let sameScores: Bool
  }

  private static func base() -> Comparison {
    var comparison = Comparison(a: .init("HelveticaNeue"), b: .init("ArialMT"))
    comparison.a.size = 20
    comparison.b?.size = 22
    comparison.calibrate()
    return comparison
  }

  private static func edited(_ body: (inout Comparison) -> Void) -> Comparison {
    var comparison = base()
    body(&comparison)
    return comparison
  }

  private static func variants() -> [Variant] {
    let catalog = FontCatalog()
    return [
      Variant(name: "base", comparison: base(), sameInput: true, sameScores: true),
      Variant(
        name: "linked size up",
        comparison: edited { $0.set(.size, to: 30, side: .a, catalog: catalog) },
        sameInput: true, sameScores: true),
      Variant(
        name: "linked size down from B",
        comparison: edited { $0.set(.size, to: 11, side: .b, catalog: catalog) },
        sameInput: true, sameScores: true),
      Variant(
        name: "linked size clamps B",
        comparison: edited { $0.set(.size, to: 140, side: .a, catalog: catalog) },
        sameInput: false, sameScores: false),
      Variant(
        name: "unlinked B size",
        comparison: edited {
          $0.appearanceLocked = false
          $0.set(.size, to: 30, side: .b, catalog: catalog)
        },
        sameInput: false, sameScores: false),
      Variant(
        name: "recalibrated sizes",
        comparison: edited {
          $0.appearanceLocked = false
          $0.set(.size, to: 40, side: .a, catalog: catalog)
          $0.set(.size, to: 44, side: .b, catalog: catalog)
        },
        sameInput: true, sameScores: true),
      Variant(
        name: "linked tracking",
        comparison: edited { $0.set(.tracking, to: 0.05, side: .a, catalog: catalog) },
        sameInput: false, sameScores: false),
      Variant(
        name: "feature",
        comparison: edited { $0.a.features["ot.liga"] = 0 }, sameInput: false, sameScores: true),
      Variant(
        name: "axis",
        comparison: edited { $0.b?.axes[tagNumber("wght")] = 700 }, sameInput: false,
        sameScores: true),
      Variant(
        name: "font A",
        comparison: edited { $0.a = .init("Georgia") }, sameInput: false, sameScores: false),
      Variant(
        name: "swapped",
        comparison: edited { $0.swap() }, sameInput: false, sameScores: false),
      Variant(
        name: "presentation",
        comparison: edited {
          $0.mode = .glyph
          $0.selectedGlyph = "g"
          $0.shape = false
          $0.spacing = true
          $0.frequency = false
        }, sameInput: true, sameScores: true),
    ]
  }

  private static func input(_ comparison: Comparison) -> DifferenceInput {
    DifferenceInput(a: comparison.a, b: comparison.b!)
  }

  @Test func retainedScoresMatchAFromScratchRecomputationWheneverTheInputIsEqual() async throws {
    let variants = Self.variants()
    let reference = Self.input(variants[0].comparison)
    var scores: [[GlyphDifference]] = []
    for variant in variants {
      let comparison = variant.comparison
      let input = Self.input(comparison)
      #expect(
        (input == reference) == variant.sameInput, "input equality for \(variant.name)")
      let computed = try await DifferenceEngine().scores(
        a: comparison.a, b: comparison.b!, sample: "")
      scores.append(computed)
      if variant.sameInput { #expect(computed == scores[0], "retained scores for \(variant.name)") }
      if !variant.sameScores {
        #expect(computed != scores[0], "changed scores for \(variant.name)")
      }
    }
    for (index, first) in variants.enumerated() {
      for (offset, second) in variants[(index + 1)...].enumerated()
      where Self.input(first.comparison) == Self.input(second.comparison) {
        #expect(
          scores[index] == scores[index + 1 + offset],
          "\(first.name) and \(second.name) share an input")
      }
    }
  }

  @Test func rawConfigurationsAtOtherAbsoluteSizesScoreTheSame() {
    let glyphs = ["a", "g", "R", "1", "@", "&"]
    let reference = Self.base()
    let reduced = Self.variants().filter { $0.sameInput }.map(\.comparison)
    for comparison in reduced {
      let b = comparison.b!
      for glyph in glyphs {
        let expected = Differences.compare(glyph, a: reference.a, b: reference.b!)
        let actual = Differences.compare(glyph, a: comparison.a, b: b)
        #expect(abs(expected.shape - actual.shape) < 1e-3, "shape \(glyph) at \(comparison.a.size)")
        #expect(
          abs(expected.spacing - actual.spacing) < 1e-6, "spacing \(glyph) at \(comparison.a.size)")
      }
    }
  }

  @Test func calibratedRatiosSurviveFloatingPointDrift() {
    var comparison = Self.base()
    let reference = Self.input(comparison)
    let catalog = FontCatalog()
    var drifted = 0
    for size in stride(from: 10.5, through: 100, by: 0.5) {
      comparison.set(.size, to: size, side: .a, catalog: catalog)
      let b = comparison.b!.size
      if 22 * b / comparison.a.size != 22 * 1.1 { drifted += 1 }
      #expect(Self.input(comparison) == reference, "size \(size)")
    }
    #expect(drifted > 0)
  }
}
