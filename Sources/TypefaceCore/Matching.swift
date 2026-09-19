import Foundation

public struct MatchOptions: Equatable, Sendable {
  public var weight = true
  public var xHeight = false
  public var tracking = false
  public init() {}
  public var isEmpty: Bool { !weight && !xHeight && !tracking }
}

/// The applied result and the result of enabling each preview option.
public struct MatchPreview: Equatable, Sendable {
  public let proposed: FontConfiguration
  public let weight: FontConfiguration
  public let xHeight: FontConfiguration
  public let tracking: FontConfiguration
}

public enum Matching {
  public static func proposal(_ comparison: Comparison, options: MatchOptions, catalog: FontCatalog)
    -> FontConfiguration?
  {
    guard let b = comparison.b,
      FontRenderer.isAvailable(comparison.a), FontRenderer.isAvailable(b)
    else { return nil }
    return fit(
      reference: comparison.a, candidate: b, text: comparison.text, options: options,
      catalog: catalog)
  }

  public static func preview(_ comparison: Comparison, options: MatchOptions, catalog: FontCatalog)
    -> MatchPreview?
  {
    guard let b = comparison.b,
      let proposed = proposal(comparison, options: options, catalog: catalog)
    else {
      return nil
    }
    func including(_ option: WritableKeyPath<MatchOptions, Bool>) -> FontConfiguration {
      var enabled = options
      enabled[keyPath: option] = true
      return fit(
        reference: comparison.a, candidate: b, text: comparison.text, options: enabled,
        catalog: catalog)
    }
    return MatchPreview(
      proposed: proposed, weight: including(\.weight), xHeight: including(\.xHeight),
      tracking: including(\.tracking))
  }

  private static func fit(
    reference a: FontConfiguration, candidate: FontConfiguration, text: String,
    options: MatchOptions, catalog: FontCatalog
  ) -> FontConfiguration {
    var b = candidate
    // Numeric weight matching is deliberately a heuristic, not a perceptual model.
    if options.weight { b.set(.weight, to: a.weight, catalog: catalog) }
    if options.xHeight, let left = FontRenderer.xHeight(config: a, size: a.size),
      let right = FontRenderer.xHeight(config: b, size: b.size)
    {
      if right > 0 { b.set(.size, to: b.size * left / right, catalog: catalog) }
    }
    if options.tracking {
      let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
