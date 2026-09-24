import Foundation

public struct FontFitOptions: Hashable, Sendable {
  public var axes: Set<UInt32>
  public var features: Set<String>
  public var tracking = true
  public var size = false

  public init(config: FontConfiguration) {
    axes = Set(config.face.axes.map(\.id))
    features = Set(config.face.features.filter { !$0.isAutomatic }.map(\.id))
  }

  public var isEmpty: Bool { axes.isEmpty && features.isEmpty && !tracking && !size }
}

public struct FontFitBudget: Sendable {
  public let seconds: Double
  public let evaluations: Int
  public static let quick = FontFitBudget(seconds: 3, evaluations: 256)
  public static let refine = FontFitBudget(seconds: 15, evaluations: 2048)
  public init(seconds: Double, evaluations: Int) {
    self.seconds = max(0, seconds)
    self.evaluations = max(1, evaluations)
  }
}

public struct FontFitResult: Sendable {
  public let proposed: FontConfiguration
  public let originalScore: SimilarityScore
  public let score: SimilarityScore
  public let evaluations: Int
  public let finished: Bool
  public var improved: Bool {
    score.total < originalScore.total - SimilarityScore.improvementTolerance
  }

  public init(
    proposed: FontConfiguration, originalScore: SimilarityScore, score: SimilarityScore,
    evaluations: Int, finished: Bool
  ) {
    self.proposed = proposed
    self.originalScore = originalScore
    self.score = score
    self.evaluations = evaluations
    self.finished = finished
  }
}

struct FontFitDomain: Sendable {
  struct Dimension: Sendable {
    let property: AppearanceProperty
    let range: ClosedRange<Double>

    func value(_ config: FontConfiguration) -> Double {
      switch property {
      case .size: config.size
      case .tracking: config.tracking
      case .weight: config.weight
      case .axis(let id): config.axes[id] ?? range.lowerBound
      }
    }

    func setting(_ config: FontConfiguration, value: Double) -> FontConfiguration {
      var config = config
      let bounded = value.clamped(to: range)
      switch property {
      case .size: config.size = bounded
      case .tracking: config.tracking = bounded
      case .weight: config.axes[tagNumber("wght")] = bounded
      case .axis(let id): config.axes[id] = bounded
      }
      return config
    }
  }

  let original: FontConfiguration
  let options: FontFitOptions
  let dimensions: [Dimension]
  let features: [FontFeature]
  private let allFeatures: [FontFeature]

  init(
    original: FontConfiguration, options: FontFitOptions, availableFeatures: [FontFeature]? = nil
  ) {
    self.original = original
    self.options = options
    dimensions =
      original.face.axes.filter {
        options.axes.contains($0.id) && $0.maximum > $0.minimum
      }.map { Dimension(property: .axis($0.id), range: $0.minimum...$0.maximum) }
      + (options.tracking ? [Dimension(property: .tracking, range: -0.12...0.15)] : [])
      + (options.size ? [Dimension(property: .size, range: 10...144)] : [])
    allFeatures = availableFeatures ?? original.face.features
    features = allFeatures.filter {
      options.features.contains($0.id) && !$0.isAutomatic
    }
  }

  func constrained(_ proposed: FontConfiguration) -> FontConfiguration {
    var result = original
    for dimension in dimensions {
      result = dimension.setting(result, value: dimension.value(proposed))
    }
    for feature in features {
      if let next = setting(result, feature: feature, value: proposed.features[feature.id]) {
        result = next
      }
    }
    return result
  }

  func setting(_ config: FontConfiguration, feature: FontFeature, value: Int?) -> FontConfiguration?
  {
    guard features.contains(where: { $0.id == feature.id }) else { return nil }
    var result = config
    result.features[feature.id] = value
    if (value ?? feature.defaultValue) != 0,
      let partner = FontConfiguration.featurePartners[feature.id]
    {
      // A locked partner must retain its actual value, including its implicit default.
      let defaultValue = allFeatures.first { $0.id == partner }?.defaultValue ?? 0
      let canChangePartner = features.contains { $0.id == partner }
      if !canChangePartner, (original.features[partner] ?? defaultValue) != 0 {
        return nil
      }
      if canChangePartner { result.features[partner] = 0 }
    }
    return result
  }

  // Keep implicit defaults separate from explicit values: tracking can disable
  // default ligatures while an explicit On setting keeps them enabled.
  func categoricalSeeds(limit: Int = 32) -> [FontConfiguration] {
    var states = [original]
    for feature in features {
      var next = Set<FontConfiguration>()
      for state in states {
        for value in [Int?.none]
          + feature.options.map({ Optional($0.value) })
        {
          if let candidate = setting(state, feature: feature, value: value) {
            next.insert(candidate)
          }
          if next.count > limit { return [] }
        }
      }
      states = next.sorted { Self.order($0) < Self.order($1) }
    }
    return states
  }

  func neighbors(_ config: FontConfiguration, step: Double, priority: [String])
    -> [FontConfiguration]
  {
    var result: [FontConfiguration] = []
    for dimension in dimensions {
      let delta = step * (dimension.range.upperBound - dimension.range.lowerBound)
      for sign in [-1.0, 1.0] {
        result.append(dimension.setting(config, value: dimension.value(config) + sign * delta))
      }
      if dimension.property == .tracking { result.append(dimension.setting(config, value: 0)) }
    }
    // Joint directions permit progress along narrow valleys between coupled axes.
    for i in dimensions.indices {
      for j in dimensions.indices where j > i {
        for sign in [-1.0, 1.0] {
          let a = dimensions[i]
          let b = dimensions[j]
          let first = a.setting(
            config, value: a.value(config) + sign * step * (a.range.upperBound - a.range.lowerBound)
          )
          for secondSign in [-1.0, 1.0] {
            result.append(
              b.setting(
                first,
                value: b.value(config) + secondSign * step
                  * (b.range.upperBound - b.range.lowerBound)))
          }
        }
      }
    }
    let ordered = features.sorted {
      (priority.firstIndex(of: $0.id) ?? Int.max, $0.id) < (
        priority.firstIndex(of: $1.id) ?? Int.max, $1.id
      )
    }
    singles: for feature in ordered {
      for value in [Int?.none]
        + feature.options.map({ Optional($0.value) })
      {
        if let next = setting(config, feature: feature, value: value) { result.append(next) }
        if result.count >= 4096 { break singles }
      }
    }
    // Include paired changes even when either feature is inert in isolation.
    pairs: for (i, feature) in ordered.prefix(8).enumerated() {
      for other in ordered.prefix(8).dropFirst(i + 1) {
        for value in feature.options {
          for second in other.options {
            if let first = setting(config, feature: feature, value: value.value),
              let next = setting(first, feature: other, value: second.value)
            {
              result.append(next)
            }
            if result.count >= 4096 { break pairs }
          }
        }
      }
    }
    var seen = Set([config])
    return result.filter { seen.insert($0).inserted }
  }

  func priority(text: String) -> [String] {
    features.sorted {
      let left = $0.sample.map { text.contains($0) } ?? false
      let right = $1.sample.map { text.contains($0) } ?? false
      return left == right ? $0.id < $1.id : left
    }.map(\.id)
  }

  func category(_ config: FontConfiguration) -> String {
    features.sorted { $0.id < $1.id }.map {
      "\($0.id)=\(config.features[$0.id] ?? $0.defaultValue)"
    }.joined(separator: ",")
  }

  static func order(_ config: FontConfiguration) -> String {
    "\(config.size):\(config.tracking):"
      + config.axes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(
        separator: ",")
      + config.features.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(
        separator: ",")
  }
}
