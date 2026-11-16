import CoreText
import Foundation

/// An example verified against the selected font's actual shaping, without fallback fonts.
public struct FontFeaturePreview: Sendable {
  public let text: String
  public let before: FontConfiguration
  public let after: FontConfiguration

  public static func make(feature: FontFeature, config: FontConfiguration) -> Self? {
    guard !feature.isAutomatic, let first = feature.options.first,
      let last = feature.options.last, first != last, FontRenderer.isAvailable(config)
    else { return nil }
    var before = config
    var after = config
    before.features[feature.id] = first.value
    let selected = config.features[feature.id] ?? feature.defaultValue
    after.features[feature.id] = selected == first.value ? last.value : selected
    let preferred = feature.id == "ot.kern" ? "AV" : feature.group == .numbers ? "1820" : nil
    let candidates =
      [feature.sample, preferred].compactMap { $0 }
      + [
        "fi fl", "ff ffi ffl", "st ct", "AV", "To", "1/2", "1820", ".:", "!?", "(A)",
        "ag", "Il", "0", "ABC", "r ->", "1st", "الله", "ریال", "אל",
      ]
      + (33...126).compactMap(UnicodeScalar.init).map(String.init)
    guard
      let text = candidates.first(where: {
        !Task.isCancelled && !$0.isEmpty && FontRenderer.supports($0, config: before)
          && FontRenderer.supports($0, config: after)
          && signature($0, config: before) != signature($0, config: after)
      })
    else { return nil }
    return Self(text: text, before: before, after: after)
  }

  private struct ShapedGlyph: Equatable {
    let glyph: CGGlyph
    let position: CGPoint
    let advance: CGSize
  }

  private static func signature(_ text: String, config: FontConfiguration) -> [ShapedGlyph] {
    let line = FontRenderer.line(text, config: config, size: 21, tracking: true)
    // Core Text guarantees CTRun values in this array.
    return (CTLineGetGlyphRuns(line) as! [CTRun]).flatMap { run in
      let count = CTRunGetGlyphCount(run)
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      var advances = [CGSize](repeating: .zero, count: count)
      CTRunGetGlyphs(run, CFRange(), &glyphs)
      CTRunGetPositions(run, CFRange(), &positions)
      CTRunGetAdvances(run, CFRange(), &advances)
      return glyphs.indices.map {
        ShapedGlyph(glyph: glyphs[$0], position: positions[$0], advance: advances[$0])
      }
    }
  }
}

/// Serial searches run off the main actor and share a bounded cache across inspectors.
public actor FontFeaturePreviewEngine {
  public static let shared = FontFeaturePreviewEngine()
  private struct CachedPreviews {
    var searched: Set<String> = []
    var values: [String: FontFeaturePreview] = [:]
  }
  private var cache: [FontConfiguration: CachedPreviews] = [:]
  private var search: @Sendable (FontFeature, FontConfiguration) -> FontFeaturePreview? =
    FontFeaturePreview.make

  public init() {}

  init(search: @escaping @Sendable (FontFeature, FontConfiguration) -> FontFeaturePreview?) {
    self.search = search
  }

  public func previews(config: FontConfiguration) throws -> [String: FontFeaturePreview] {
    try previews(config: config, features: config.face.features)
  }

  public func preview(feature: FontFeature, config: FontConfiguration) throws -> FontFeaturePreview?
  {
    try previews(config: config, features: [feature])[feature.id]
  }

  private func previews(config: FontConfiguration, features: [FontFeature]) throws -> [String:
    FontFeaturePreview]
  {
    try Task.checkCancellation()
    var config = config
    config.size = 21
    config.leading = nil
    var result = cache[config] ?? CachedPreviews()
    for feature in features where !feature.isAutomatic && !result.searched.contains(feature.id) {
      try Task.checkCancellation()
      result.values[feature.id] = search(feature, config)
      result.searched.insert(feature.id)
    }
    try Task.checkCancellation()
    if cache[config] == nil && cache.count >= 8 { cache.removeAll(keepingCapacity: true) }
    // Empty results are cached too: searches without an example are the most expensive.
    cache[config] = result
    return result.values
  }
}
