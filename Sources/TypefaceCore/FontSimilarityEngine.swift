import CoreText
import Foundation

/// Native comparisons share prepared samples, but never normalize away physical size.
public actor FontSimilarityEngine {
  public static let shared = FontSimilarityEngine()

  private struct ImageKey: Hashable, Sendable {
    let config: FontConfiguration
    let text: String
    let scale: Double
    let tracking: Bool
    let radius: Float
    let shaping: [ShapedRun]
  }
  private struct ShapedRun: Hashable, Sendable {
    let font: String
    let glyphs: [CGGlyph]
    let geometry: [Double]
  }
  private struct ScoreKey: Hashable, Sendable {
    let a: FontConfiguration
    let b: FontConfiguration
    let corpus: SimilarityCorpus
    let scale: Double
  }
  private struct Sample: Sendable {
    let text: String
    let tracking: Bool
  }
  private struct Terms: Sendable {
    let geometry: Double
    let appearance: Double
    let metric: Double
  }
  /// Core Text documents font objects as safe to use from several threads at once.
  private struct SharedFont: @unchecked Sendable {
    let font: CTFont
  }
  private var images: LeastRecentlyUsed<ImageKey, SimilarityImage>
  private var scores: LeastRecentlyUsed<ScoreKey, Result<SimilarityScore, SimilarityError>>
  var cachedBytes: Int { images.bytes + scores.bytes }
  private(set) var renderCount = 0
  private let rankingConcurrency: Int

  public init(
    cacheBytes: Int = 128 * 1024 * 1024,
    rankingConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount
  ) {
    let capacity = max(0, cacheBytes)
    // A separate score budget keeps catalog-sized image churn from evicting finished scores.
    let scoreCapacity = capacity / 16
    images = .init(capacity: capacity - scoreCapacity)
    scores = .init(capacity: scoreCapacity)
    self.rankingConcurrency = max(
      1, min(rankingConcurrency, ProcessInfo.processInfo.activeProcessorCount))
  }

  // Rendering and pixel comparisons run on the concurrent executor. Only cache access
  // is actor-isolated, so catalog workers and other windows can make progress together.
  @concurrent
  public func compare(
    a: FontConfiguration, b: FontConfiguration, corpus: SimilarityCorpus = .diagnostic,
    scale: Double = 2
  ) async throws -> SimilarityScore {
    try await compare(
      a: a, b: b, corpus: corpus, scale: scale,
      concurrency: ProcessInfo.processInfo.activeProcessorCount)
  }

  @concurrent
  func compare(
    a: FontConfiguration, b: FontConfiguration, corpus: SimilarityCorpus, scale: Double,
    concurrency: Int
  ) async throws -> SimilarityScore {
    try Task.checkCancellation()
    try Self.validate(a, scale: scale)
    try Self.validate(b, scale: scale)
    guard !corpus.glyphs.isEmpty || !corpus.runs.isEmpty else { throw SimilarityError.emptyCorpus }
    let key = ScoreKey(a: a, b: b, corpus: corpus, scale: scale)
    if let cached = await cachedScore(key) { return try cached.get() }
    do {
      let score = try await measure(
        a: a, b: b, corpus: corpus, scale: scale, concurrency: concurrency)
      try Task.checkCancellation()
      await store(.success(score), for: key)
      return score
    } catch let error as SimilarityError {
      // An installed font's coverage is fixed, but a rendering failure can be transient.
      if case .unsupportedText = error { await store(.failure(error), for: key) }
      throw error
    }
  }

  @concurrent
  private func measure(
    a: FontConfiguration, b: FontConfiguration, corpus: SimilarityCorpus, scale: Double,
    concurrency: Int
  ) async throws -> SimilarityScore {
    for config in [a, b] where !corpus.requiredText.isEmpty {
      guard
        FontRenderer.supports(
          corpus.requiredText, config: config, size: config.size, tracking: true)
      else {
        throw SimilarityError.unsupportedText(config.postScriptName, corpus.requiredText)
      }
    }
    // Averaging both sizes keeps the radius, and therefore every image term, symmetric
    // even when A and B differ in point size.
    let radius = Float(max(2, min(32, (a.size + b.size) / 2 * scale / 8)))
    let samples =
      corpus.glyphs.map { Sample(text: $0, tracking: false) }
      + corpus.runs.map { Sample(text: $0, tracking: true) }
    let left: [Result<SimilarityImage, any Error>?]
    let right: [Result<SimilarityImage, any Error>?]
    if a == b {
      left = try await images(
        samples, config: a, scale: scale, radius: radius, concurrency: concurrency)
      right = left
    } else {
      async let leftImages = images(
        samples, config: a, scale: scale, radius: radius, concurrency: concurrency)
      async let rightImages = images(
        samples, config: b, scale: scale, radius: radius, concurrency: concurrency)
      (left, right) = try await (leftImages, rightImages)
    }
    // Each side stops after its first failure, so every earlier sample has both images and
    // the reported failure is the first in corpus order, preferring A's.
    let pairs = try samples.indices.map { (try left[$0]!.get(), try right[$0]!.get()) }
    let terms = try await Self.map(pairs.count, concurrency: concurrency) { index in
      let (left, right) = pairs[index]
      let difference = try left.difference(from: right)
      let l = left.measurement
      let r = right.measurement
      // Relative to A's size, which stays fixed while Match varies B's. Normalizing by the
      // mean size would shrink this term as B grows and bias Match toward larger sizes.
      let metric =
        [
          abs(l.advance - r.advance), abs(l.leftBearing - r.leftBearing),
          abs(l.rightBearing - r.rightBearing), abs(l.bounds.minY - r.bounds.minY),
          abs(l.bounds.maxY - r.bounds.maxY),
        ].map { min(1, $0 / a.size) }.reduce(0, +) / 5
      return Terms(
        geometry: difference.geometry, appearance: difference.appearance, metric: metric)
    }.map { $0! }
    var geometry = 0.0
    var appearance = 0.0
    var shaped = 0.0
    var metric = 0.0
    for (sample, term) in zip(samples, terms) {
      if sample.tracking {
        shaped += term.appearance
      } else {
        geometry += term.geometry
        appearance += term.appearance
      }
      metric += term.metric
    }
    return SimilarityScore(
      geometry: geometry / Double(max(1, corpus.glyphs.count)),
      appearance: appearance / Double(max(1, corpus.glyphs.count)),
      shapedText: shaped / Double(max(1, corpus.runs.count)),
      metrics: metric / Double(corpus.glyphs.count + corpus.runs.count))
  }

  public func rankFamilies(
    reference: FontConfiguration, catalog: FontCatalog, scale: Double = 2
  ) -> AsyncThrowingStream<FamilySimilarity, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try Self.validate(reference, scale: scale)
          guard
            let a = catalog.defaultConfiguration(in: reference.face.family, size: reference.size)
          else {
            throw SimilarityError.unavailableFont(reference.postScriptName)
          }
          // Validate the reference before returning a catalog full of misleading failures.
          _ = try await compare(
            a: a, b: a, corpus: .diagnostic, scale: scale, concurrency: rankingConcurrency)
          try await Self.rank(
            families: catalog.families, concurrency: rankingConcurrency,
            compare: { family in
              try await self.compareFamily(family, reference: a, catalog: catalog, scale: scale)
            }, receive: { continuation.yield($0) })
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Refill one worker at a time, keeping both queued work and cancellation bounded.
  static func rank(
    families: [String], concurrency: Int,
    compare: @escaping @Sendable (String) async throws -> FamilySimilarity,
    receive: @Sendable (FamilySimilarity) -> Void
  ) async throws {
    try await withThrowingTaskGroup(of: FamilySimilarity.self) { group in
      var remaining = families.makeIterator()
      for _ in 0..<min(max(1, concurrency), families.count) {
        let family = remaining.next()!
        group.addTask {
          try Task.checkCancellation()
          return try await compare(family)
        }
      }
      while let result = try await group.next() {
        try Task.checkCancellation()
        receive(result)
        if let family = remaining.next() {
          group.addTask {
            try Task.checkCancellation()
            return try await compare(family)
          }
        }
      }
    }
  }

  @concurrent
  private func compareFamily(
    _ family: String, reference: FontConfiguration, catalog: FontCatalog, scale: Double
  ) async throws -> FamilySimilarity {
    try Task.checkCancellation()
    guard let b = catalog.defaultConfiguration(in: family, size: reference.size) else {
      return .init(
        family: family, score: nil, unavailableReason: "No installed face is available.")
    }
    return try await Self.familyScore(family: family) {
      try await self.compare(
        a: reference, b: b, corpus: .diagnostic, scale: scale, concurrency: 1)
    }
  }

  static func familyScore(
    family: String, compare: @Sendable () async throws -> SimilarityScore
  ) async throws -> FamilySimilarity {
    do {
      let score = try await compare()
      return .init(family: family, score: score)
    } catch is CancellationError { throw CancellationError() } catch {
      return .init(family: family, score: nil, unavailableReason: error.localizedDescription)
    }
  }

  static func validate(_ config: FontConfiguration, scale: Double) throws {
    guard config.size.isFinite, (1...144).contains(config.size), config.tracking.isFinite,
      (-0.12...0.15).contains(config.tracking), scale.isFinite, (1...4).contains(scale),
      config.axes.values.allSatisfy(\.isFinite)
    else { throw SimilarityError.invalidConfiguration }
    guard FontRenderer.isAvailable(config) else {
      throw SimilarityError.unavailableFont(config.postScriptName)
    }
  }

  /// `measure` relies on indices starting in order and none starting after `stop`.
  static func map<T: Sendable>(
    _ count: Int, concurrency: Int, stop: @escaping @Sendable (T) -> Bool = { _ in false },
    transform: @escaping @Sendable (Int) async throws -> T
  ) async throws -> [T?] {
    var results = [T?](repeating: nil, count: count)
    guard concurrency > 1 else {
      for index in 0..<count {
        let result = try await transform(index)
        results[index] = result
        if stop(result) { break }
      }
      return results
    }
    try await withThrowingTaskGroup(of: (Int, T).self) { group in
      var next = 0
      var stopped = false
      func start() {
        guard !stopped, next < count else { return }
        let index = next
        next += 1
        group.addTask { (index, try await transform(index)) }
      }
      for _ in 0..<concurrency { start() }
      while let (index, result) = try await group.next() {
        results[index] = result
        stopped = stopped || stop(result)
        start()
      }
    }
    return results
  }

  @concurrent
  private func images(
    _ samples: [Sample], config: FontConfiguration, scale: Double, radius: Float,
    concurrency: Int
  ) async throws -> [Result<SimilarityImage, any Error>?] {
    let keys = samples.map { Self.plainKey($0, config: config, scale: scale, radius: radius) }
    let cached = await cachedImages(keys).map {
      $0.map { Result<SimilarityImage, any Error>.success($0) }
    }
    guard cached.contains(where: { $0 == nil }) else { return cached }
    let font = SharedFont(font: FontRenderer.font(config))
    return try await Self.map(
      samples.count, concurrency: concurrency, stop: { (try? $0.get()) == nil },
      transform: { index in
        if let image = cached[index] { return image }
        return try await self.render(
          samples[index], config: config, font: font, scale: scale, radius: radius)
      })
  }

  @concurrent
  private func render(
    _ sample: Sample, config: FontConfiguration, font: SharedFont, scale: Double, radius: Float
  ) async throws -> Result<SimilarityImage, any Error> {
    try Task.checkCancellation()
    let line = FontRenderer.line(
      sample.text, config: config, font: font.font, size: config.size, tracking: sample.tracking)
    // Features may be inert for this sample. Axes remain in the key because they can
    // change outlines even when the glyph IDs and positions are identical.
    let key =
      Self.plainKey(sample, config: config, scale: scale, radius: radius)
      ?? ImageKey(
        config: Self.base(config), text: sample.text, scale: scale, tracking: sample.tracking,
        radius: radius, shaping: Self.shaping(line))
    if let cached = await cachedImage(key) { return .success(cached) }
    guard FontRenderer.supports(line, font: font.font) else {
      return .failure(SimilarityError.unsupportedText(config.postScriptName, sample.text))
    }
    let result = Result<SimilarityImage, any Error> {
      SimilarityImage(try SimilarityImage.rasterize(line, scale: scale, radius: radius))
    }
    try Task.checkCancellation()
    if case .success(let image) = result { _ = await store(image, for: key) }
    return result
  }

  /// Without features or tracking, the configuration alone determines shaping, so the key
  /// can omit it and a cache hit needs no Core Text work.
  private static func plainKey(
    _ sample: Sample, config: FontConfiguration, scale: Double, radius: Float
  ) -> ImageKey? {
    guard config.features.isEmpty, !sample.tracking || config.tracking == 0 else { return nil }
    return ImageKey(
      config: base(config), text: sample.text, scale: scale, tracking: sample.tracking,
      radius: radius, shaping: [])
  }

  private static func base(_ config: FontConfiguration) -> FontConfiguration {
    var base = config
    base.features = [:]
    base.tracking = 0
    return base
  }

  private func cachedScore(_ key: ScoreKey) -> Result<SimilarityScore, SimilarityError>? {
    if let result = scores.value(for: key) { return result }
    // At equal sizes every term is symmetric, so the reverse comparison has the same score.
    // Failures are not: they name whichever side fails first.
    guard key.a.size == key.b.size,
      case .success(let score)? = scores.value(
        for: ScoreKey(a: key.b, b: key.a, corpus: key.corpus, scale: key.scale))
    else { return nil }
    return .success(score)
  }

  private func cachedImages(_ keys: [ImageKey?]) -> [SimilarityImage?] {
    var result: [SimilarityImage?] = []
    for key in keys { result.append(key.flatMap { images.value(for: $0) }) }
    return result
  }

  private func cachedImage(_ key: ImageKey) -> SimilarityImage? {
    images.value(for: key)
  }

  private func store(_ result: Result<SimilarityScore, SimilarityError>, for key: ScoreKey) {
    let bytes =
      256 + key.corpus.requiredText.utf8.count
      + (key.corpus.glyphs + key.corpus.runs).reduce(0) { $0 + $1.utf8.count }
    scores.insert(result, bytes: bytes, for: key)
  }

  /// Evicted images are returned so that freeing them does not serialize on the actor.
  private func store(_ result: SimilarityImage, for key: ImageKey) -> [SimilarityImage] {
    renderCount += 1
    let bytes =
      result.byteCount + key.text.utf8.count + 256
      + key.shaping.reduce(0) {
        $0 + $1.font.utf8.count + $1.glyphs.count * 2 + $1.geometry.count * 8
      }
    return images.insert(result, bytes: bytes, for: key)
  }

  private static func shaping(_ line: CTLine) -> [ShapedRun] {
    (CTLineGetGlyphRuns(line) as! [CTRun]).map { run in
      let count = CTRunGetGlyphCount(run)
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      var advances = [CGSize](repeating: .zero, count: count)
      CTRunGetGlyphs(run, CFRange(), &glyphs)
      CTRunGetPositions(run, CFRange(), &positions)
      CTRunGetAdvances(run, CFRange(), &advances)
      let attributes = CTRunGetAttributes(run) as NSDictionary
      let font = attributes[kCTFontAttributeName] as! CTFont
      let geometry = glyphs.indices.flatMap {
        [
          Double(positions[$0].x), Double(positions[$0].y), Double(advances[$0].width),
          Double(advances[$0].height),
        ]
      }
      return ShapedRun(
        font: CTFontCopyPostScriptName(font) as String, glyphs: glyphs, geometry: geometry)
    }
  }
}
