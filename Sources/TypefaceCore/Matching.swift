import Foundation

public struct MatchOptions: Equatable, Sendable {
  public var weight = true
  public var xHeight = false
  public var tracking = false
  public init() {}
  public var isEmpty: Bool { !weight && !xHeight && !tracking }
}

public enum Matching {
  public static func proposal(_ comparison: Comparison, options: MatchOptions, catalog: FontCatalog)
    -> FontConfiguration?
  {
    guard var b = comparison.b else { return nil }
    let a = comparison.a
    // Numeric weight matching is deliberately a heuristic, not a perceptual model.
    if options.weight { b.set(.weight, to: a.weight, catalog: catalog) }
    if options.xHeight, let left = FontRenderer.xHeight(config: a, size: a.size),
      let right = FontRenderer.xHeight(config: b, size: b.size)
    {
      if right > 0 { b.set(.size, to: b.size * left / right, catalog: catalog) }
    }
    if options.tracking {
      let text = comparison.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      if text.count > 1, FontRenderer.supports(text, config: a),
        FontRenderer.supports(text, config: b)
      {
        b = matchingTracking(text, reference: a, candidate: b, catalog: catalog)
      }
    }
    return b
  }

  private static func matchingTracking(
    _ text: String, reference: FontConfiguration, candidate: FontConfiguration, catalog: FontCatalog
  ) -> FontConfiguration {
    func width(_ config: FontConfiguration) -> Double {
      FontRenderer.measure(text, config: config, size: config.size, tracking: true).advance
    }
    let target = width(reference)
    var best = candidate
    var error = abs(width(best) - target)
    func consider(_ config: FontConfiguration) {
      let nextError = abs(width(config) - target)
      if nextError < error {
        best = config
        error = nextError
      }
    }
    var zero = candidate
    zero.tracking = 0
    consider(zero)
    // Measure Core Text's response, which depends on shaped clusters, including ligatures.
    // Zero tracking can enable automatic ligatures, so fit the two nonzero ranges separately.
    for range in [-0.12 ... -0.000001, 0.000001...0.15] {
      var low = candidate
      var high = candidate
      low.tracking = range.lowerBound
      high.tracking = range.upperBound
      let lowWidth = width(low)
      let difference = width(high) - lowWidth
      guard abs(difference) > 1e-9 else { continue }
      let fraction = ((target - lowWidth) / difference).clamped(to: 0...1)
      var fitted = candidate
      fitted.set(
        .tracking, to: range.lowerBound + fraction * (range.upperBound - range.lowerBound),
        catalog: catalog)
      consider(fitted)
    }
    return best
  }
}
