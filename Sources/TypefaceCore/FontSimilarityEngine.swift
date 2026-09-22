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
  private struct Entry<Value> {
    let value: Value
    let bytes: Int
    var access: UInt64
  }
  private var images: [ImageKey: Entry<SimilarityImage>] = [:]
  private var scores: [ScoreKey: Entry<SimilarityScore>] = [:]
  private var clock: UInt64 = 0
  private(set) var cachedBytes = 0
  private let capacity: Int
  private let rankingConcurrency: Int

  public init(
    cacheBytes: Int = 128 * 1024 * 1024,
    rankingConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount
  ) {
    capacity = max(0, cacheBytes)
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
    try Task.checkCancellation()
    try Self.validate(a, scale: scale)
    try Self.validate(b, scale: scale)
    guard !corpus.glyphs.isEmpty || !corpus.runs.isEmpty else { throw SimilarityError.emptyCorpus }
    let key = ScoreKey(a: a, b: b, corpus: corpus, scale: scale)
    if let cached = await cachedScore(key) { return cached }
    for config in [a, b] where !corpus.requiredText.isEmpty {
      guard
        FontRenderer.supports(
          corpus.requiredText, config: config, size: config.size, tracking: true)
      else {
        throw SimilarityError.unsupportedText(config.postScriptName, corpus.requiredText)
      }
    }
    // Averaging both sizes keeps the radius, and therefore the score, symmetric
    // even when A and B differ in point size.
    let radius = Float(max(2, min(32, (a.size + b.size) / 2 * scale / 8)))
    var geometry = 0.0
    var appearance = 0.0
    var shaped = 0.0
    var metric = 0.0
    for (tracking, texts) in [(false, corpus.glyphs), (true, corpus.runs)] {
      for text in texts {
        try Task.checkCancellation()
        async let leftImage = image(
          text, config: a, scale: scale, tracking: tracking, radius: radius)
        async let rightImage = image(
          text, config: b, scale: scale, tracking: tracking, radius: radius)
        let (left, right) = try await (leftImage, rightImage)
        let difference = try left.difference(from: right)
        if tracking {
          shaped += difference.appearance
        } else {
          geometry += difference.geometry
          appearance += difference.appearance
        }
        let l = left.measurement
        let r = right.measurement
        metric +=
          [
            abs(l.advance - r.advance), abs(l.leftBearing - r.leftBearing),
            abs(l.rightBearing - r.rightBearing), abs(l.bounds.minY - r.bounds.minY),
            abs(l.bounds.maxY - r.bounds.maxY),
          ].map { min(1, $0 / a.size) }.reduce(0, +) / 5
      }
    }
    let result = SimilarityScore(
      geometry: geometry / Double(max(1, corpus.glyphs.count)),
      appearance: appearance / Double(max(1, corpus.glyphs.count)),
      shapedText: shaped / Double(max(1, corpus.runs.count)),
      metrics: metric / Double(corpus.glyphs.count + corpus.runs.count))
    try Task.checkCancellation()
    await store(result, for: key)
    return result
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
          _ = try await compare(a: a, b: a, scale: scale)
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
    do {
      let score = try await compare(a: reference, b: b, scale: scale)
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

  @concurrent
  private func image(
    _ text: String, config: FontConfiguration, scale: Double, tracking: Bool, radius: Float
  ) async throws -> SimilarityImage {
    var config = config
    if !tracking { config.tracking = 0 }
    let shaping = Self.shaping(text, config: config, tracking: tracking)
    var base = config
    base.features = [:]
    base.tracking = 0
    // Features may be inert for this sample. Axes remain in the key because they can
    // change outlines even when the glyph IDs and positions are identical.
    let key = ImageKey(
      config: base, text: text, scale: scale, tracking: tracking, radius: radius, shaping: shaping)
    if let cached = await cachedImage(key) { return cached }
    try Task.checkCancellation()
    let result = try SimilarityImage.render(
      text, config: config, scale: scale, tracking: tracking, radius: radius)
    try Task.checkCancellation()
    await store(result, for: key)
    return result
  }

  private func cachedScore(_ key: ScoreKey) -> SimilarityScore? {
    guard var entry = scores[key] else { return nil }
    clock += 1
    entry.access = clock
    scores[key] = entry
    return entry.value
  }

  private func cachedImage(_ key: ImageKey) -> SimilarityImage? {
    guard var entry = images[key] else { return nil }
    clock += 1
    entry.access = clock
    images[key] = entry
    return entry.value
  }

  private func store(_ result: SimilarityScore, for key: ScoreKey) {
    let bytes =
      256 + key.corpus.requiredText.utf8.count
      + (key.corpus.glyphs + key.corpus.runs).reduce(0) { $0 + $1.utf8.count }
    clock += 1
    // Another comparison may have filled the same entry while this one was rendering.
    cachedBytes += bytes - (scores[key]?.bytes ?? 0)
    scores[key] = Entry(value: result, bytes: bytes, access: clock)
    evict()
  }

  private func store(_ result: SimilarityImage, for key: ImageKey) {
    let bytes =
      result.byteCount + key.text.utf8.count + 256
      + key.shaping.reduce(0) {
        $0 + $1.font.utf8.count + $1.glyphs.count * 2 + $1.geometry.count * 8
      }
    clock += 1
    cachedBytes += bytes - (images[key]?.bytes ?? 0)
    images[key] = Entry(value: result, bytes: bytes, access: clock)
    evict()
  }

  private static func shaping(_ text: String, config: FontConfiguration, tracking: Bool)
    -> [ShapedRun]
  {
    let line = FontRenderer.line(text, config: config, size: config.size, tracking: tracking)
    return (CTLineGetGlyphRuns(line) as! [CTRun]).map { run in
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

  private func evict() {
    while cachedBytes > capacity {
      let image = images.min { $0.value.access < $1.value.access }
      let score = scores.min { $0.value.access < $1.value.access }
      if let image, image.value.access <= (score?.value.access ?? .max) {
        cachedBytes -= image.value.bytes
        images.removeValue(forKey: image.key)
      } else if let score {
        cachedBytes -= score.value.bytes
        scores.removeValue(forKey: score.key)
      }
    }
  }
}
