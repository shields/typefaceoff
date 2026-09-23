import CoreText
import Foundation
import Testing

@testable import TypefaceCore

extension SimilarityBenchmark {
  struct BaselineScore: Codable, Equatable {
    let total: Double?
    let bits: [String]
    let error: String?

    init(_ score: SimilarityScore?, error: String? = nil) {
      total = score?.total
      bits = [score?.geometry, score?.appearance, score?.shapedText, score?.metrics].compactMap {
        $0.map { String($0.bitPattern, radix: 16) }
      }
      self.error = error
    }
  }

  @Test(.benchmark)
  func exportBaselineScores() async throws {
    let catalog = FontCatalog()
    var scores: [String: BaselineScore] = [:]
    for size in [14.0, 22, 36] {
      let engine = FontSimilarityEngine()
      for family in ["Helvetica Neue", "Times New Roman", "Courier New", "Skia"] {
        let reference = try #require(catalog.defaultConfiguration(in: family, size: size))
        for try await result in await engine.rankFamilies(reference: reference, catalog: catalog) {
          scores["rank \(reference.postScriptName) \(size) \(result.family)"] = BaselineScore(
            result.score, error: result.unavailableReason)
        }
      }
    }
    let helvetica = FontConfiguration("HelveticaNeue")
    let arial = FontConfiguration("ArialMT")
    var larger = arial
    larger.size = 30
    var tracked = helvetica
    tracked.tracking = 0.05
    tracked.features = ["ot.kern": 0]
    let skia = try #require(catalog.defaultConfiguration(in: "Skia", size: 22))
    var varied = skia
    varied.axes[tagNumber("wght")] = 1.2
    varied.axes[tagNumber("wdth")] = 1.05
    varied.tracking = 0.025
    let reading = SimilarityCorpus.fitting(
      reference: helvetica, candidate: arial, text: Sample.reading.text)
    let cases: [(String, FontConfiguration, FontConfiguration, SimilarityCorpus, Double)] = [
      ("sizes", helvetica, larger, .diagnostic, 2),
      ("sizes reversed", larger, helvetica, .diagnostic, 2),
      ("tracking and features", tracked, arial, .diagnostic, 2),
      ("axes", varied, skia, .diagnostic, 2),
      ("axes reversed", skia, varied, .diagnostic, 2),
      ("reading", helvetica, arial, reading, 2),
      ("reading screening", helvetica, arial, reading.screening, 2),
      ("scale 1", helvetica, arial, .diagnostic, 1),
      ("scale 3", helvetica, arial, .diagnostic, 3),
    ]
    let engine = FontSimilarityEngine()
    for (name, a, b, corpus, scale) in cases {
      scores["pair \(name)"] = BaselineScore(
        try await engine.compare(a: a, b: b, corpus: corpus, scale: scale))
    }
    try write(scores, to: "baseline-scores.json")
    if let path = ProcessInfo.processInfo.environment["TYPEFACEOFF_BASELINE_SCORES"] {
      let expected = try JSONDecoder().decode(
        [String: BaselineScore].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
      #expect(scores.keys.sorted() == expected.keys.sorted())
      let changed = expected.keys.sorted().filter { scores[$0] != expected[$0] }
      #expect(changed.isEmpty, "\(changed.count) scores changed, including \(changed.prefix(5))")
    }
  }
}

extension SimilarityBenchmark {
  struct Scenario: Encodable {
    let name: String
    let workers: Int
    let seconds: Double
    let firstResult: Double
    let finalTopTen: Double
    let renders: Int
    let families: Int
  }
  struct CatalogProfile: Encodable {
    let families: Int
    let defaultConfigurationSeconds: Double
    let scenarios: [Scenario]
  }

  @Test(.benchmark)
  func profileInstalledCatalog() async throws {
    let start = ContinuousClock.now
    let catalog = FontCatalog()
    let defaults = catalog.families.compactMap { catalog.defaultConfiguration(in: $0, size: 22) }
    let parse = seconds(since: start)
    let helvetica = try #require(catalog.defaultConfiguration(in: "Helvetica Neue", size: 22))
    let times = try #require(catalog.defaultConfiguration(in: "Times New Roman", size: 22))
    let larger = try #require(catalog.defaultConfiguration(in: "Helvetica Neue", size: 24))
    let cores = ProcessInfo.processInfo.activeProcessorCount
    var scenarios: [Scenario] = []
    let engine = FontSimilarityEngine()
    for (name, reference) in [
      ("cold", helvetica), ("repeat", helvetica), ("new reference", times), ("size 24", larger),
    ] {
      scenarios.append(
        try await rank(name, engine: engine, workers: cores, reference: reference, catalog: catalog)
      )
    }
    for workers in Array(Set([1, 4, 8, cores].map { min($0, cores) })).sorted() {
      scenarios.append(
        try await rank(
          "unbounded cache",
          engine: FontSimilarityEngine(cacheBytes: .max, rankingConcurrency: workers),
          workers: workers, reference: helvetica, catalog: catalog))
    }
    try write(
      CatalogProfile(
        families: defaults.count, defaultConfigurationSeconds: parse, scenarios: scenarios),
      to: "catalog-profile.json")
  }

  private func rank(
    _ name: String, engine: FontSimilarityEngine, workers: Int, reference: FontConfiguration,
    catalog: FontCatalog
  ) async throws -> Scenario {
    let renders = await engine.renderCount
    let start = ContinuousClock.now
    var arrivals: [String: Double] = [:]
    var totals: [String: Double] = [:]
    for try await result in await engine.rankFamilies(reference: reference, catalog: catalog) {
      arrivals[result.family] = seconds(since: start)
      totals[result.family] = result.score?.total
    }
    let elapsed = seconds(since: start)
    let top = totals.sorted { $0.value < $1.value }.prefix(10).map(\.key)
    return Scenario(
      name: name, workers: workers, seconds: elapsed, firstResult: arrivals.values.min() ?? 0,
      finalTopTen: top.compactMap { arrivals[$0] }.max() ?? 0,
      renders: await engine.renderCount - renders, families: arrivals.count)
  }

  struct StageProfile: Encodable {
    let size: Double
    let fonts: Int
    let unsupported: Int
    let seconds: [String: Double]
    let fontMilliseconds: [String: Double]
    let bytesPerFont: [String: Double]
  }

  @Test(.benchmark)
  func profileStages() throws {
    let catalog = FontCatalog()
    let corpus = SimilarityCorpus.diagnostic
    let texts = corpus.glyphs.map { ($0, false) } + corpus.runs.map { ($0, true) }
    var profiles: [StageProfile] = []
    for size in [14.0, 22, 36, 72, 144] {
      let families = catalog.families.enumerated().filter { size == 22 || $0.offset % 8 == 0 }
      let configs = families.compactMap { catalog.defaultConfiguration(in: $0.element, size: size) }
      let radius = Float(max(2, min(32, size * 2 / 8)))
      let reference = try #require(catalog.defaultConfiguration(in: "Helvetica Neue", size: size))
      let references = try texts.map {
        try SimilarityImage.render(
          $0.0, config: reference, scale: 2, tracking: $0.1, radius: radius)
      }
      var totals: [String: Double] = [:]
      var perFont: [Double] = []
      var memory = 0
      var pixelBytes = 0
      var fieldBytes = 0
      var unsupported = 0
      for config in configs {
        var font = 0.0
        var pixels = Data()
        var fields = Data()
        for (index, (text, tracking)) in texts.enumerated() {
          var start = ContinuousClock.now
          func lap(_ stage: String) {
            let elapsed = seconds(since: start)
            totals[stage, default: 0] += elapsed
            font += elapsed
            start = .now
          }
          let raster: SimilarityImage.Raster
          do {
            raster = try SimilarityImage.rasterize(
              text, config: config, scale: 2, tracking: tracking, radius: radius)
          } catch SimilarityError.unsupportedText {
            unsupported += 1
            continue
          }
          lap("rasterize")
          _ = SimilarityImage.signedField(
            raster.pixels, width: raster.width, height: raster.height, radius: radius)
          lap("field")
          for sigma in SimilarityImage.sigmas {
            _ = SimilarityImage.blur(
              raster.pixels, width: raster.width, height: raster.height, sigma: sigma)
          }
          lap("blur")
          let image = SimilarityImage(raster)
          start = .now
          _ = try image.difference(from: references[index])
          lap("difference")
          memory += image.byteCount
          pixels.append(contentsOf: raster.pixels.map { UInt8(($0 * 255).rounded()) })
          let ink = SimilarityImage.distanceTransform(
            raster.pixels.map { $0 >= 0.5 }, width: raster.width, height: raster.height)
          let background = SimilarityImage.distanceTransform(
            raster.pixels.map { $0 < 0.5 }, width: raster.width, height: raster.height)
          let squared = raster.pixels.indices.map {
            Int16(raster.pixels[$0] >= 0.5 ? -min(1025, background[$0]) : min(1025, ink[$0]))
          }
          squared.withUnsafeBytes { fields.append(contentsOf: $0) }
        }
        perFont.append(font)
        pixelBytes += try (pixels as NSData).compressed(using: .lzfse).length
        fieldBytes += try ((pixels + fields) as NSData).compressed(using: .lzfse).length
      }
      let sorted = perFont.sorted()
      try #require(!sorted.isEmpty)
      let count = Double(max(1, configs.count))
      profiles.append(
        StageProfile(
          size: size, fonts: configs.count, unsupported: unsupported, seconds: totals,
          fontMilliseconds: [
            "p50": sorted[sorted.count / 2] * 1000, "p95": sorted[sorted.count * 95 / 100] * 1000,
          ],
          bytesPerFont: [
            "memory": Double(memory) / count, "pixels": Double(pixelBytes) / count,
            "pixelsAndField": Double(fieldBytes) / count,
          ]))
    }
    try write(profiles, to: "stage-profile.json")
  }

  struct FitProfile: Encodable {
    let name: String
    let refine: Bool
    let evaluations: Int
    let seconds: Double
    let supportsSeconds: Double
    let texts: Int
  }

  @Test(.benchmark)
  func profileFit() async throws {
    let catalog = FontCatalog()
    let skia = try #require(catalog.defaultConfiguration(in: "Skia", size: 22))
    var target = skia
    target.axes[tagNumber("wght")] = 1.2
    target.axes[tagNumber("wdth")] = 1.05
    target.tracking = 0.025
    var profiles: [FitProfile] = []
    for (name, a, b) in [
      ("Helvetica Neue to Arial", FontConfiguration("HelveticaNeue"), FontConfiguration("ArialMT")),
      ("Skia target to Skia", target, skia),
    ] {
      let corpus = SimilarityCorpus.fitting(reference: a, candidate: b, text: Sample.reading.text)
      let supportsStart = ContinuousClock.now
      for config in [a, b] {
        #expect(
          FontRenderer.supports(
            corpus.requiredText, config: config, size: config.size, tracking: true))
      }
      let supports = seconds(since: supportsStart)
      let engine = FontFitEngine(similarity: FontSimilarityEngine())
      for refine in [false, true] {
        let start = ContinuousClock.now
        var final: FontFitResult?
        for try await result in await engine.fit(
          a: a, b: b, options: .init(config: b), corpus: corpus, catalog: catalog,
          budget: refine ? .refine : .quick, refine: refine)
        { final = result }
        let result = try #require(final)
        profiles.append(
          FitProfile(
            name: name, refine: refine, evaluations: result.evaluations,
            seconds: seconds(since: start), supportsSeconds: supports,
            texts: corpus.glyphs.count + corpus.runs.count))
      }
    }
    try write(profiles, to: "fit-profile.json")
  }

  private func write(_ value: some Encodable, to name: String) throws {
    let folder = try benchmarkFolder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: folder.appendingPathComponent(name))
  }
}
