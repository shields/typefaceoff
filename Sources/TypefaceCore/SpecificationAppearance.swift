import Foundation

extension Comparison {
  public func hasAppearanceChanges(catalog: FontCatalog) -> Bool {
    var defaults = self
    defaults.resetAppearance(catalog: catalog)
    return a != defaults.a || b != defaults.b
  }

  public mutating func resetAppearance(catalog: FontCatalog) {
    let locked = appearanceLocked
    let previousLink = link
    appearanceLocked = false
    for side in [Side.a, .b] {
      if let config = self[side], FontRenderer.isAvailable(config) {
        resetAppearance(side: side, catalog: catalog)
      }
    }
    appearanceLocked = locked
    if FontRenderer.isAvailable(a), b.map({ FontRenderer.isAvailable($0) }) == true {
      calibrate()
    } else {
      link = previousLink
    }
  }
}

extension SpecificationSetting {
  public static func settings(a: [FontAxis], b: [FontAxis]) -> [Self] {
    let ids = Set(a.map(\.id))
    return [.size, .leading, .tracking]
      + (a + b.filter { !ids.contains($0.id) }).map {
        .axis($0.id)
      }
  }

  public func defaultEntry(for config: FontConfiguration) -> SpecificationValue.Entry {
    switch self {
    case .size: .number(22)
    case .leading: .automatic
    case .tracking: .number(0)
    case .axis(let id):
      .number(Self.defaultAxisValue(config.face.axes.first { $0.id == id }!, size: config.size))
    }
  }

  static func defaultAxisValue(_ axis: FontAxis, size: Double) -> Double {
    axis.tag == "opsz" ? size.clamped(to: axis.minimum...axis.maximum) : axis.defaultValue
  }

  public func isChanged(in config: FontConfiguration) -> Bool {
    if case .number(let value) = defaultEntry(for: config) {
      return value != self.value(in: config)
    }
    return config.leading != nil
  }

  public var logarithmic: Bool { self == .size || self == .leading }

  public func position(_ value: Double, in range: ClosedRange<Double>) -> Double {
    guard range.lowerBound != range.upperBound else { return 0 }
    let value = value.clamped(to: range)
    return logarithmic
      ? log(value / range.lowerBound) / log(range.upperBound / range.lowerBound)
      : (value - range.lowerBound) / (range.upperBound - range.lowerBound)
  }

  public func value(at position: Double, in range: ClosedRange<Double>) -> Double {
    let position = position.clamped(to: 0...1)
    if position == 0 { return range.lowerBound }
    if position == 1 { return range.upperBound }
    return logarithmic
      ? (range.lowerBound * pow(range.upperBound / range.lowerBound, position)).clamped(to: range)
      : range.lowerBound + position * (range.upperBound - range.lowerBound)
  }

  public func reset(in comparison: inout Comparison, catalog: FontCatalog) {
    let locked = comparison.appearanceLocked
    comparison.appearanceLocked = false
    for side in [Side.a, .b] {
      if let config = comparison[side], FontRenderer.isAvailable(config), rules(for: config) != nil
      {
        apply(defaultEntry(for: config), to: &comparison, side: side, both: false, catalog: catalog)
      }
    }
    comparison.appearanceLocked = locked
    guard let b = comparison.b, FontRenderer.isAvailable(comparison.a), FontRenderer.isAvailable(b)
    else { return }
    let relation = AppearanceLink(a: comparison.a, b: b)
    switch self {
    case .size: comparison.link?.sizeRatio = relation.sizeRatio
    case .leading: comparison.link?.leadingOffset = relation.leadingOffset
    case .tracking: comparison.link?.trackingOffset = relation.trackingOffset
    case .axis(let id):
      comparison.link?.axisOffsets[id] = relation.axisOffsets[id]
      if id == tagNumber("wght") { comparison.link?.weightOffset = relation.weightOffset }
    }
  }

  public func relation(in comparison: Comparison, locale: Locale = .current) -> String? {
    guard FontRenderer.isAvailable(comparison.a),
      comparison.b.map({ FontRenderer.isAvailable($0) }) == true,
      comparison.appearanceLocked, let link = comparison.link
    else { return nil }
    let value: Double
    let suffix: String
    switch self {
    case .size:
      guard abs(link.sizeRatio - 1) >= 0.0005 else { return nil }
      return "×" + SpecificationNumber.format(link.sizeRatio, precision: 3, locale: locale)
    case .leading:
      value = link.leadingOffset
      suffix = " pt"
    case .tracking:
      value = link.trackingOffset
      suffix = " em"
    case .axis(let id):
      value = link.axisOffsets[id] ?? 0
      suffix = ""
    }
    guard abs(value) >= 0.0005 else { return nil }
    let precision: Int
    if case .axis = self {
      precision = SpecificationNumber.precision([value])
    } else {
      precision = 3
    }
    return (value < 0 ? "−" : "+")
      + SpecificationNumber.format(abs(value), precision: precision, locale: locale) + suffix
  }
}
