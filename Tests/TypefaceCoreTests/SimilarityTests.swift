import CoreText
import Foundation
import Synchronization
import Testing

@testable import TypefaceCore

@Suite(.serialized) struct SimilarityTests {
  let corpus = SimilarityCorpus(glyphs: ["a", "I", " ", "é"], runs: ["AV To", "a a", "fi fl"])

  @Test func identitySymmetryPhysicalSizeAndTracking() async throws {
    let engine = FontSimilarityEngine()
    let a = FontConfiguration("HelveticaNeue")
    let b = FontConfiguration("ArialMT")
    let identity = try await engine.compare(a: a, b: a, corpus: corpus)
    #expect(identity.total == 0)
    let ab = try await engine.compare(a: a, b: b, corpus: corpus)
    let ba = try await engine.compare(a: b, b: a, corpus: corpus)
    #expect(ab == ba)
    #expect(ab.total > 0 && ab.total <= 1)
    var changed = a
    changed.size *= 1.4
    #expect(try await engine.compare(a: a, b: changed, corpus: corpus).total > ab.total)
    changed = a
    changed.tracking = 0.08
    let tracked = try await engine.compare(a: a, b: changed, corpus: corpus)
    #expect(tracked.geometry == 0 && tracked.appearance == 0)
    #expect(tracked.shapedText > 0 && tracked.metrics > 0)
    #expect(try await engine.compare(a: a, b: b, corpus: corpus) == ab)
    #expect(await engine.cachedBytes > 0)
  }

  @Test(arguments: ["HelveticaNeue", "TimesNewRomanPSMT"], [1.0, 2.0])
  func rasterRetainsBaselineWhenRunBoundsChange(font: String, scale: Double) throws {
    let config = FontConfiguration(font)
    for (glyph, neighbor) in [("F", "g"), ("g", "F"), ("F", "Á")] {
      let single = try SimilarityImage.render(
        glyph, config: config, scale: scale, tracking: false, radius: 3)
      // Keep the neighboring glyph outside the first glyph's padded raster.
      let run = try SimilarityImage.render(
        "\(glyph)    \(neighbor)", config: config, scale: scale, tracking: false, radius: 3)
      #expect(
        run.measurement.bounds.minY < single.measurement.bounds.minY
          || run.measurement.bounds.maxY > single.measurement.bounds.maxY)
      let pixels = (0..<run.height).flatMap { row in
        (0..<single.width).map { column in
          run.value(run.pixels, x: single.x + column, y: run.y + row)
        }
      }
      let cropped = SimilarityImage(
        x: single.x, y: run.y, width: single.width, height: run.height, pixels: pixels,
        radius: single.radius)
      let difference = try single.difference(from: cropped)
      #expect(difference.geometry == 0)
      #expect(difference.appearance < 1e-6)
    }
  }

  @Test func distanceTransformMatchesBruteForceAndBlankPaddingIsIrrelevant() throws {
    let width = 19
    let height = 17
    let sites = (0..<width * height).map { $0 % 17 == 3 || $0 % 43 == 8 }
    let distances = SimilarityImage.distanceTransform(sites, width: width, height: height)
    for index in sites.indices {
      let expected = sites.indices.filter { sites[$0] }.map {
        Float(
          pow(Double(index % width - $0 % width), 2) + pow(Double(index / width - $0 / width), 2))
      }.min()
      #expect(distances[index] == expected)
    }
    func image(padding: Int, shift: Int = 0, blank: Bool = false) -> SimilarityImage {
      let side = 25 + padding * 2
      let pixels = (0..<side * side).map { index -> Float in
        let x = index % side - padding
        let y = index / side - padding
        return !blank && (9 + shift...13 + shift).contains(x) && (8...16).contains(y) ? 1 : 0
      }
      return SimilarityImage(
        x: -padding, y: -padding, width: side, height: side, pixels: pixels, radius: 3)
    }
    let base = image(padding: 0)
    let padded = image(padding: 9)
    #expect(try base.difference(from: padded).geometry == 0)
    // Vectorized convolution can change rounding by a few Float ulps with alignment.
    #expect(try base.difference(from: padded).appearance < 1e-6)
    let shifted = try base.difference(from: image(padding: 0, shift: 1))
    let paddedShifted = try padded.difference(from: image(padding: 9, shift: 1))
    #expect(shifted.geometry == paddedShifted.geometry && shifted.geometry > 0)
    #expect(abs(shifted.appearance - paddedShifted.appearance) < 1e-6 && shifted.appearance > 0)
    #expect(
      try image(padding: 0, blank: true).difference(from: image(padding: 9, blank: true)).geometry
        == 0)
    #expect(
      try image(padding: 0, blank: true).difference(from: image(padding: 9, blank: true)).appearance
        == 0)
    #expect(try base.difference(from: image(padding: 0, blank: true)).appearance == 1)
  }

  @Test func coverageErrorsAndEvictionRemainExplicit() async throws {
    let engine = FontSimilarityEngine(cacheBytes: 600)
    let a = FontConfiguration("ArialMT")
    let b = FontConfiguration("TimesNewRomanPSMT")
    let score = try await engine.compare(a: a, b: b, corpus: corpus, scale: 1)
    #expect(score.total > 0)
    #expect(await engine.cachedBytes <= 600)
    let second = SimilarityCorpus(glyphs: ["z"], runs: ["AV"])
    _ = try await engine.compare(a: b, b: a, corpus: second, scale: 1)
    #expect(await engine.cachedBytes <= 600)
    #expect(try await engine.compare(a: a, b: b, corpus: corpus, scale: 1) == score)
    await #expect(throws: SimilarityError.unavailableFont("NoSuchFont-Example")) {
      try await engine.compare(a: .init("NoSuchFont-Example"), b: a)
    }
    for scale in [0.0, 5.0, .nan] {
      await #expect(throws: SimilarityError.invalidConfiguration) {
        try await engine.compare(a: a, b: b, scale: scale)
      }
    }
    await #expect(throws: SimilarityError.emptyCorpus) {
      try await engine.compare(a: a, b: a, corpus: .init(glyphs: [], runs: []))
    }
    let missing = "\u{10FFFF}"
    for corpus in [
      SimilarityCorpus(glyphs: [missing], runs: []),
      .init(glyphs: ["a"], runs: [], requiredText: missing),
    ] {
      await #expect(throws: SimilarityError.unsupportedText(a.postScriptName, missing)) {
        try await engine.compare(a: a, b: a, corpus: corpus)
      }
    }
    #expect(throws: SimilarityError.renderingFailed) {
      try SimilarityImage.render(
        String(repeating: "M", count: 20000), config: a, scale: 4, tracking: false, radius: 8)
    }
    let cancelled = Task {
      try Task.checkCancellation()
      return try await engine.compare(a: a, b: a, corpus: corpus)
    }
    cancelled.cancel()
    _ = await cancelled.result
    for error in [
      SimilarityError.unavailableFont("A"), .unsupportedText("A", missing), .invalidConfiguration,
      .emptyCorpus, .renderingFailed,
    ] {
      #expect(!error.localizedDescription.isEmpty)
    }
    #expect(FamilySimilarity(family: "A", score: nil, unavailableReason: "missing").id == "A")
  }

  @Test func corporaAndDefaultConfigurationsAreDeterministic() throws {
    let reference = FontConfiguration(try #require(FontCatalog().preferredFace(in: "Skia")).id)
    let text = (0..<200).map { "word\($0)" }.joined(separator: " ")
    let corpus = SimilarityCorpus.fitting(reference: reference, candidate: reference, text: text)
    #expect(corpus.requiredText == text)
    #expect(corpus.runs.filter { $0.hasPrefix("word") }.count == 128)
    #expect(corpus.runs.contains("word0") && corpus.runs.contains("word99"))
    #expect(corpus.screening.glyphs.count <= 16 && corpus.screening.runs.count == 8)
    #expect(SimilarityCorpus.version == 1 && SimilarityScore.version == 1)
    #expect(SimilarityCorpus(glyphs: ["", "a", "a"], runs: ["", "a"]).glyphs == ["a"])
    let catalog = FontCatalog()
    let defaults = try #require(catalog.defaultConfiguration(in: "Skia", size: 31))
    #expect(defaults.size == 31 && defaults.tracking == 0 && defaults.features.isEmpty)
    #expect(defaults.axes == FontConfiguration(defaults.postScriptName).axes)
    #expect(catalog.defaultConfiguration(in: "NoSuchFamily", size: 22) == nil)
    let instances = FontCatalog(
      descriptors: ["Skia-Regular_Light", "Skia-Regular_Bold", "Skia-Regular_Black-Condensed"].map {
        CTFontDescriptorCreateWithNameAndSize($0 as CFString, 22)
      })
    let instance = try #require(instances.defaultConfiguration(in: "Skia", size: 22))
    #expect(instance.postScriptName != "Skia-Regular_Black-Condensed")
    #expect(instance.axes == FontConfiguration(instance.postScriptName).axes)
    #expect(
      instance.axes
        != Dictionary(uniqueKeysWithValues: instance.face.axes.map { ($0.id, $0.defaultValue) }))
    #expect(catalog.preferredFace(in: "Futura")?.id == "Futura-Medium")
    let opticalSize = FontAxis(
      id: tagNumber("opsz"), name: "Optical size", minimum: 8, maximum: 144, defaultValue: 14)
    let weight = FontAxis(
      id: tagNumber("wght"), name: "Weight", minimum: 100, maximum: 900, defaultValue: 400)
    var sized = FontConfiguration("HelveticaNeue")
    for (size, expected) in [(11.0, 11.0), (200, 144), (4, 8)] {
      sized.size = size
      sized.matchOpticalSize([opticalSize, weight])
      #expect(sized.axes == [opticalSize.id: expected])
    }
  }

  @Test func familyRankingUsesDefaultsAndReportsUnsupportedFamilies() async throws {
    let descriptors = ["ArialMT", "HelveticaNeue", "AppleColorEmoji"].map { name in
      CTFontDescriptorCreateWithNameAndSize(name as CFString, 22)
    }
    let catalog = FontCatalog(descriptors: descriptors)
    let engine = FontSimilarityEngine(cacheBytes: 8 * 1024 * 1024)
    var reference = FontConfiguration("ArialMT")
    reference.tracking = 0.1
    reference.features = ["ot.kern": 0]
    var results: [FamilySimilarity] = []
    for try await result in await engine.rankFamilies(
      reference: reference, catalog: catalog, scale: 1)
    {
      results.append(result)
    }
    #expect(results.count == catalog.families.count)
    #expect(results.first { $0.family == "Arial" }?.score?.total == 0)
    #expect(results.first { $0.family == "Apple Color Emoji" }?.unavailableReason != nil)
    await #expect(throws: SimilarityError.unavailableFont("NoSuchFont")) {
      for try await _ in await engine.rankFamilies(reference: .init("NoSuchFont"), catalog: catalog)
      {}
    }
  }
}

extension SimilarityTests {
  @Test func absentCatalogFacesAndCancelledRankingNeverCompareFallbacks() async throws {
    let engine = FontSimilarityEngine()
    let a = FontConfiguration("ArialMT")
    await #expect(throws: SimilarityError.unavailableFont(a.postScriptName)) {
      for try await _ in await engine.rankFamilies(
        reference: a, catalog: FontCatalog(descriptors: nil))
      {}
    }
    let missing = CTFontDescriptorCreateWithAttributes(
      [
        kCTFontFamilyNameAttribute: "Missing", kCTFontNameAttribute: "TypefaceOff-Missing-Face",
      ] as CFDictionary)
    let catalog = FontCatalog(descriptors: [
      CTFontDescriptorCreateWithNameAndSize("ArialMT" as CFString, 22), missing,
    ])
    var foundMissing = false
    for try await result in await engine.rankFamilies(reference: a, catalog: catalog, scale: 1) {
      if result.family == "Missing" {
        foundMissing = true
        #expect(result.score == nil && result.unavailableReason != nil)
      }
    }
    #expect(foundMissing)
    let task = Task {
      for try await _ in await engine.rankFamilies(reference: a, catalog: FontCatalog()) {
        try Task.checkCancellation()
      }
    }
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()
    _ = await task.result
    let small = FontSimilarityEngine(cacheBytes: 150_000)
    let first = try await small.compare(a: a, b: a, corpus: corpus, scale: 1)
    for glyph in ["g", "j", "x", "W"] {
      _ = try await small.compare(a: a, b: a, corpus: .init(glyphs: [glyph], runs: []), scale: 1)
    }
    #expect(await small.cachedBytes <= 150_000)
    #expect(try await small.compare(a: a, b: a, corpus: corpus, scale: 1) == first)
  }
}

extension SimilarityTests {
  @Test func concurrentComparisonsPreserveScoresAndCacheAccounting() async throws {
    let a = FontConfiguration("HelveticaNeue")
    let b = FontConfiguration("ArialMT")
    let serial = FontSimilarityEngine()
    let expected = try await serial.compare(a: a, b: b, corpus: corpus, scale: 1)
    let concurrent = FontSimilarityEngine()
    try await withThrowingTaskGroup(of: SimilarityScore.self) { group in
      for _ in 0..<8 {
        group.addTask { try await concurrent.compare(a: a, b: b, corpus: corpus, scale: 1) }
      }
      for try await score in group { #expect(score == expected) }
    }
    #expect(await concurrent.cachedBytes == serial.cachedBytes)

    let catalog = FontCatalog(
      descriptors: ["HelveticaNeue", "ArialMT", "Georgia", "AppleColorEmoji"].map {
        CTFontDescriptorCreateWithNameAndSize($0 as CFString, 22)
      })
    var sequential: [String: FamilySimilarity] = [:]
    for try await result in await FontSimilarityEngine(rankingConcurrency: 1).rankFamilies(
      reference: a, catalog: catalog, scale: 1)
    {
      sequential[result.family] = result
    }
    var parallel: [String: FamilySimilarity] = [:]
    for try await result in await concurrent.rankFamilies(reference: a, catalog: catalog, scale: 1)
    {
      parallel[result.family] = result
    }
    #expect(parallel.keys.sorted() == sequential.keys.sorted())
    for (family, result) in sequential {
      #expect(parallel[family]?.score == result.score)
      #expect(parallel[family]?.unavailableReason == result.unavailableReason)
    }
  }

  @Test func rankingWorkersAreBoundedRefilledAndCancelledTogether() async throws {
    let (started, continuation) = AsyncStream<String>.makeStream()
    let gate = FamilyComparisonGate(started: continuation)
    let results = Mutex<[String]>([])
    let task = Task {
      try await FontSimilarityEngine.rank(
        families: ["A", "B", "C", "D"], concurrency: 2,
        compare: { try await gate.compare($0) },
        receive: { result in
          results.withLock { $0.append(result.family) }
        })
    }
    var iterator = started.makeAsyncIterator()
    let first = try #require(await iterator.next())
    let second = try #require(await iterator.next())
    #expect(Set([first, second]) == ["A", "B"])
    #expect(await gate.activeCount == 2)
    await gate.finish(second)
    #expect(await iterator.next() == "C")
    #expect(results.withLock { $0 } == [second])
    #expect(await gate.activeCount == 2)
    await gate.finish("C")
    #expect(await iterator.next() == "D")
    await gate.finish("D")
    await gate.finish(first)
    try await task.value
    #expect(results.withLock { $0.count } == 4)
    #expect(await gate.activeCount == 0)

    let cancelled = Task {
      try await FontSimilarityEngine.rank(
        families: ["E", "F", "G", "H"], concurrency: 2,
        compare: { try await gate.compare($0) }, receive: { _ in Issue.record("Cancelled result") })
    }
    _ = await iterator.next()
    _ = await iterator.next()
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(await gate.activeCount == 0)
    #expect(await gate.compared == Set(["A", "B", "C", "D", "E", "F"]))
  }

  @Test func acceleratedBlurMatchesTheScalarGaussianIncludingSmallImages() {
    for (width, height) in [(1, 1), (2, 3), (19, 23)] {
      let pixels = (0..<width * height).map { Float($0 % 7) / 6 }
      for sigma in [0.75, 1.5] {
        let radius = Int(ceil(3 * sigma))
        let raw = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let kernel = raw.map { $0 / raw.reduce(0, +) }
        let result = SimilarityImage.blur(pixels, width: width, height: height, sigma: sigma)
        for y in 0..<height {
          for x in 0..<width {
            var expected = 0.0
            for dy in -radius...radius where (0..<height).contains(y + dy) {
              for dx in -radius...radius where (0..<width).contains(x + dx) {
                expected +=
                  Double(pixels[(y + dy) * width + x + dx]) * kernel[dx + radius]
                  * kernel[dy + radius]
              }
            }
            #expect(abs(Double(result[y * width + x]) - expected) < 1e-6)
          }
        }
      }
    }
  }
}

private actor FamilyComparisonGate {
  let started: AsyncStream<String>.Continuation
  private var pending: [String: AsyncStream<Void>.Continuation] = [:]
  private(set) var compared: Set<String> = []
  var activeCount: Int { pending.count }

  init(started: AsyncStream<String>.Continuation) { self.started = started }

  func compare(_ family: String) async throws -> FamilySimilarity {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    pending[family] = continuation
    compared.insert(family)
    started.yield(family)
    defer { pending.removeValue(forKey: family) }
    for await _ in stream {}
    try Task.checkCancellation()
    return .init(family: family, score: nil)
  }

  func finish(_ family: String) { pending[family]?.finish() }
}
