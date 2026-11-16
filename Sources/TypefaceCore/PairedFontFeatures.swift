public struct PairedFontFeature: Identifiable, Sendable {
  public let a: FontFeature?
  public let b: FontFeature?
  public var feature: FontFeature { (a ?? b)! }
  public var id: String { feature.id }

  public subscript(_ side: Side) -> FontFeature? { side == .a ? a : b }

  public static func rows(a: [FontFeature], b: [FontFeature]) -> [Self] {
    let byA = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0) })
    let byB = Dictionary(uniqueKeysWithValues: b.map { ($0.id, $0) })
    return (a.map(\.id) + b.map(\.id).filter { byA[$0] == nil }).map {
      Self(a: byA[$0], b: byB[$0])
    }
  }

  public func isChanged(a: [String: Int], b: [String: Int]) -> Bool {
    changed(feature: self.a, values: a) || changed(feature: self.b, values: b)
  }

  public func differs(a: [String: Int], b: [String: Int]) -> Bool {
    if let first = self.a, let second = self.b {
      return (a[id] ?? first.defaultValue) != (b[id] ?? second.defaultValue)
    }
    return isChanged(a: a, b: b)
  }

  private func changed(feature: FontFeature?, values: [String: Int]) -> Bool {
    guard let feature else { return false }
    return (values[feature.id] ?? feature.defaultValue) != feature.defaultValue
  }
}
