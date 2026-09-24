import Foundation

public enum Side: String, Sendable { case a, b }
public enum ComparisonMode: String, Sendable { case text, glyph }
public enum AppearanceProperty: Hashable, Sendable {
  case size, tracking, weight
  case axis(UInt32)
}

public struct FontConfiguration: Hashable, Sendable {
  public var postScriptName: String
  public var size: Double = 22
  public var tracking: Double = 0
  public var axes: [UInt32: Double] = [:]
  public var features: [String: Int] = [:]

  public init(_ postScriptName: String) {
    self.postScriptName = postScriptName
    axes = Dictionary(
      uniqueKeysWithValues: face.axes.map { ($0.id, face.coordinates[$0.id] ?? $0.defaultValue) })
  }

  public var face: FontFace { FontFace.named(postScriptName) }
  public var weight: Double { axes[tagNumber("wght")] ?? face.weight }

  public mutating func replaceFace(_ next: FontFace) {
    postScriptName = next.id
    axes = Dictionary(
      uniqueKeysWithValues: next.axes.map {
        ($0.id, (axes[$0.id] ?? $0.defaultValue).clamped(to: $0.minimum...$0.maximum))
      })
    features = features.filter { key, _ in next.features.contains { $0.id == key } }
  }

  public mutating func set(_ property: AppearanceProperty, to value: Double, catalog: FontCatalog) {
    guard value.isFinite else { return }
    switch property {
    case .size: size = value.clamped(to: 10...144)
    case .tracking: tracking = value.clamped(to: -0.12...0.15)
    case .weight:
      if let axis = face.axes.first(where: { $0.tag == "wght" }) {
        axes[axis.id] = value.clamped(to: axis.minimum...axis.maximum)
      } else {
        let current = face
        let choices = catalog.faces(in: current.family).filter { $0.italic == current.italic }
        let nearest = choices.reduce(current) { best, candidate in
          abs(candidate.weight - value) < abs(best.weight - value) ? candidate : best
        }
        if nearest.id != current.id { replaceFace(nearest) }
      }
    case .axis(let id):
      if let axis = face.axes.first(where: { $0.id == id }) {
        axes[id] = value.clamped(to: axis.minimum...axis.maximum)
      }
    }
  }
}

public struct AppearanceLink: Equatable, Sendable {
  public var sizeRatio: Double
  public var weightOffset: Double
  public var trackingOffset: Double
  public var axisOffsets: [UInt32: Double]

  public init(a: FontConfiguration, b: FontConfiguration) {
    sizeRatio = b.size / a.size
    weightOffset = b.weight - a.weight
    trackingOffset = b.tracking - a.tracking
    axisOffsets = a.axes.reduce(into: [:]) { values, axis in
      if let other = b.axes[axis.key] { values[axis.key] = other - axis.value }
    }
  }
}

public struct Comparison: Equatable, Sendable {
  public var a: FontConfiguration
  public var b: FontConfiguration?
  public var removedB: FontConfiguration?
  public var appearanceLocked = true
  public var link: AppearanceLink?
  public var mode: ComparisonMode = .text
  public var sample: Sample = .reading
  public var customText = ""
  public var selectedGlyph = "a"
  public var shape = true
  public var spacing = false
  public var frequency = true

  public init(
    a: FontConfiguration = .init("HelveticaNeue"), b: FontConfiguration? = .init("ArialMT")
  ) {
    self.a = a
    self.b = b
    calibrate()
  }

  public var text: String { sample == .custom ? customText : sample.text }

  public mutating func calibrate() { link = b.map { AppearanceLink(a: a, b: $0) } }

  public subscript(side: Side) -> FontConfiguration? {
    get { side == .a ? a : b }
    set {
      if side == .a { if let newValue { a = newValue } } else { b = newValue }
    }
  }

  public mutating func set(
    _ property: AppearanceProperty, to value: Double, side: Side, catalog: FontCatalog
  ) {
    guard var edited = self[side] else { return }
    edited.set(property, to: value, catalog: catalog)
    self[side] = edited
    guard appearanceLocked, let link, var other = self[side == .a ? .b : .a] else { return }
    let sign = side == .a ? 1.0 : -1.0
    let target: Double
    switch property {
    case .size: target = edited.size * (side == .a ? link.sizeRatio : 1 / link.sizeRatio)
    case .tracking: target = edited.tracking + sign * link.trackingOffset
    case .weight: target = edited.weight + sign * link.weightOffset
    case .axis(let id):
      guard let value = edited.axes[id], other.axes[id] != nil else { return }
      target = value + sign * (link.axisOffsets[id] ?? 0)
    }
    other.set(property, to: target, catalog: catalog)
    self[side == .a ? .b : .a] = other
  }

  public mutating func selectFace(_ face: FontFace, side: Side, catalog: FontCatalog) {
    self[side]?.replaceFace(face)
    for axis in face.axes {
      self[side]?.axes[axis.id] = face.coordinates[axis.id] ?? axis.defaultValue
    }
    if let config = self[side], appearanceLocked, var other = self[side == .a ? .b : .a] {
      let options = catalog.faces(in: other.face.family).filter { $0.italic == face.italic }
      if other.face.italic != face.italic,
        let next = options.min(by: {
          abs($0.weight - other.weight) < abs($1.weight - other.weight)
        })
      {
        other.replaceFace(next)
      }
      self[side == .a ? .b : .a] = other
      set(.weight, to: config.weight, side: side, catalog: catalog)
    }
  }

  public mutating func selectFamily(_ family: String?, side: Side, catalog: FontCatalog) {
    guard let family else {
      if side == .b {
        removedB = b
        b = nil
        calibrate()
      }
      return
    }
    if side == .b, b == nil, let previous = removedB, previous.face.family == family {
      b = previous
    } else if let face = catalog.preferredFace(in: family, italic: (self[side] ?? a).face.italic) {
      let previous = self[side] ?? a
      var next = previous
      next.replaceFace(face)
      next.set(.weight, to: previous.weight, catalog: catalog)
      self[side] = next
    }
    calibrate()
  }

  public mutating func swap() {
    guard let previous = b else { return }
    b = a
    a = previous
    calibrate()
  }

  public mutating func resetAppearance(side: Side, catalog: FontCatalog) {
    for target in appearanceLocked && b != nil ? [Side.a, .b] : [side] {
      guard let previous = self[target] else { continue }
      var next = previous
      if FontRenderer.isAvailable(previous),
        let regular = catalog.preferredFace(in: previous.face.family)
      {
        next = FontConfiguration(regular.id)
        next.axes = Dictionary(uniqueKeysWithValues: regular.axes.map { ($0.id, $0.defaultValue) })
        next.features = previous.features
      }
      next.size = 22
      next.tracking = 0
      self[target] = next
    }
    calibrate()
  }

  public mutating func setFeature(_ feature: FontFeature, value: Int, side: Side) {
    guard !feature.isAutomatic else { return }
    self[side]?.features[feature.id] = value
    let partners = [
      "ot.tnum": "ot.pnum", "ot.pnum": "ot.tnum", "ot.lnum": "ot.onum", "ot.onum": "ot.lnum",
      "ot.sups": "ot.subs", "ot.subs": "ot.sups",
    ]
    if value != 0, let partner = partners[feature.id] { self[side]?.features[partner] = 0 }
  }
}

extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(range.upperBound, max(range.lowerBound, self))
  }
}
