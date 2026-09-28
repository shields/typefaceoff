import Foundation

public struct GlyphDifference: Identifiable, Hashable, Sendable {
  // String identity is canonical equivalence, which would merge distinct candidates
  // (U+037E GREEK QUESTION MARK and ';') into one SwiftUI identity.
  public var id: [Unicode.Scalar] { Array(glyph.unicodeScalars) }
  public let glyph: String
  public let shape: Double
  public let spacing: Double
  public let frequency: Double?
  public var weight: Double { CharacterFrequency.weight(forFrequency: frequency) }

  public init(glyph: String, shape: Double, spacing: Double) {
    self.glyph = glyph
    self.shape = shape
    self.spacing = spacing
    frequency = CharacterFrequency.frequency(of: glyph)
  }

  public func weighted(_ value: Double, frequency: Bool) -> Double {
    frequency ? value * weight : value
  }
}

public enum Differences {
  public static func inkDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
    precondition(a.count == b.count)
    var intersection = 0.0
    var union = 0.0
    for (left, right) in zip(a, b) {
      intersection += Double(min(left, right))
      union += Double(max(left, right))
    }
    return union == 0 ? 0 : 1 - intersection / union
  }

  public static func compare(_ glyph: String, a: FontConfiguration, b: FontConfiguration)
    -> GlyphDifference
  {
    let sizes = [192.0, 192 * b.size / a.size]
    let configs = [a, b]
    let metrics = zip(configs, sizes).map { FontRenderer.measure(glyph, config: $0, size: $1) }
    let advances = zip(metrics, zip(configs, sizes)).map { $0.advance + $1.0.tracking * $1.1 }
    let spacing =
      (abs(advances[0] - advances[1]) + abs(metrics[0].leftBearing - metrics[1].leftBearing)
        + abs(metrics[0].rightBearing - metrics[1].rightBearing)) / (3 * 192)
    let ascent = max(0, metrics[0].bounds.maxY, metrics[1].bounds.maxY)
    let descent = max(0, -min(metrics[0].bounds.minY, metrics[1].bounds.minY))
    let width = max(1, metrics[0].bounds.width, metrics[1].bounds.width)
    let height = max(1, ascent + descent)
    let scale = min(1, 504 / max(width, height))
    let masks = configs.indices.map { index in
      FontRenderer.mask(
        glyph, config: configs[index], size: sizes[index] * scale,
        width: Int(ceil(width * scale)) + 8, height: Int(ceil(height * scale)) + 8,
        origin: CGPoint(x: 4 - metrics[index].bounds.minX * scale, y: 4 + descent * scale))
    }
    return GlyphDifference(glyph: glyph, shape: inkDifference(masks[0], masks[1]), spacing: spacing)
  }

  public static func candidates(sample: String) -> [String] {
    // Dedup by scalars: String equality is canonical equivalence, which would drop
    // U+037E GREEK QUESTION MARK from a sample as a duplicate of the fixed ';'.
    var seen = Set<[Unicode.Scalar]>()
    var result: [String] = []
    for character in String((33...126).compactMap(UnicodeScalar.init).map(Character.init))
      + sample
    {
      guard !String(character).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        continue
      }
      if seen.insert(Array(character.unicodeScalars)).inserted { result.append(String(character)) }
    }
    return result.sorted()
  }

  public static func ranked(
    _ scores: [GlyphDifference], shape: Bool, spacing: Bool, frequency: Bool
  )
    -> [GlyphDifference]
  {
    if shape != spacing {
      return scores.sorted {
        let left = $0.weighted(shape ? $0.shape : $0.spacing, frequency: frequency)
        let right = $1.weighted(shape ? $1.shape : $1.spacing, frequency: frequency)
        return left == right ? $0.glyph < $1.glyph : left > right
      }
    }
    let shapeRanks = percentiles(scores, key: \.shape)
    let spacingRanks = percentiles(scores, key: \.spacing)
    // Both maps contain every input glyph, including ties and duplicate glyphs.
    return scores.sorted {
      let left = $0.weighted(shapeRanks[$0.id]! + spacingRanks[$0.id]!, frequency: frequency)
      let right = $1.weighted(shapeRanks[$1.id]! + spacingRanks[$1.id]!, frequency: frequency)
      return left == right ? $0.glyph < $1.glyph : left > right
    }
  }

  private static func percentiles(
    _ scores: [GlyphDifference], key: KeyPath<GlyphDifference, Double>
  ) -> [[Unicode.Scalar]: Double] {
    let sorted = scores.sorted { $0[keyPath: key] < $1[keyPath: key] }
    var result: [[Unicode.Scalar]: Double] = [:]
    var start = 0
    while start < sorted.count {
      var end = start + 1
      while end < sorted.count, abs(sorted[start][keyPath: key] - sorted[end][keyPath: key]) < 1e-9
      { end += 1 }
      let value =
        sorted[start][keyPath: key] > 1e-9
        ? Double(start + end - 1) / 2 / Double(max(1, sorted.count - 1)) : 0
      for index in start..<end { result[sorted[index].id] = value }
      start = end
    }
    return result
  }

  public static func highlights(
    _ scores: [GlyphDifference], text: String, shape: Bool, spacing: Bool, frequency: Bool
  ) -> Set<String> {
    // Scalar-exact, like id and candidates: canonical equivalence would count a candidate as
    // present in text because a different, canonically equal character appears there instead.
    let present = Set(text.map { Array($0.unicodeScalars) })
    var selected = Set<String>()
    for isShape in [true, false] where isShape ? shape : spacing {
      selected.formUnion(
        ranked(scores, shape: isShape, spacing: !isShape, frequency: frequency)
          .filter { present.contains($0.id) && (isShape ? $0.shape : $0.spacing) > 1e-9 }
          .prefix(8).map(\.glyph))
    }
    return selected
  }
}

/// Work runs off the main actor. Callers cancel obsolete requests between glyphs.
public actor DifferenceEngine {
  private struct Key: Hashable {
    let a: FontConfiguration
    let b: FontConfiguration
    let candidates: [String]
  }
  private var cache: [Key: [GlyphDifference]] = [:]
  public init() {}

  public func scores(a: FontConfiguration, b: FontConfiguration, sample: String) throws
    -> [GlyphDifference]
  {
    var left = a
    var right = b
    left.size = 22
    right.size = 22 * b.size / a.size
    let candidates = Differences.candidates(sample: sample)
    let key = Key(a: left, b: right, candidates: candidates)
    if let cached = cache[key] { return cached }
    var result: [GlyphDifference] = []
    for glyph in candidates {
      try Task.checkCancellation()
      if FontRenderer.supports(glyph, config: left), FontRenderer.supports(glyph, config: right) {
        result.append(Differences.compare(glyph, a: left, b: right))
      }
    }
    if cache.count >= 8 { cache.removeAll(keepingCapacity: true) }
    cache[key] = result
    return result
  }
}
