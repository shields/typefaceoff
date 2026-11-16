import Foundation

public enum SpecificationNumber {
  public static func precision(_ values: [Double], computed: Bool = false) -> Int {
    if computed { return 3 }
    let rounded = values.map { ($0 * 1000).rounded() / 1000 }
    for digits in 0..<3 {
      let scale = pow(10.0, Double(digits))
      if rounded.allSatisfy({ abs($0 * scale - ($0 * scale).rounded()) < 0.000_001 }) {
        return digits
      }
    }
    return 3
  }

  public static func format(_ value: Double, precision: Int, locale: Locale = .current) -> String {
    let scale = pow(10.0, Double(precision))
    let rounded = (value * scale).rounded() / scale
    return (rounded == 0 ? 0 : rounded).formatted(
      .number.precision(.fractionLength(precision)).grouping(.never).locale(locale))
  }

  public static func parse(_ text: String, locale: Locale = .current) -> Double? {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.isLenient = false
    formatter.usesGroupingSeparator = false
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var range = NSRange(location: 0, length: text.utf16.count)
    var result: AnyObject?
    do { try formatter.getObjectValue(&result, for: text, range: &range) } catch { return nil }
    guard range.length == text.utf16.count, let value = (result as? NSNumber)?.doubleValue,
      value.isFinite
    else { return nil }
    return value
  }
}

public struct SpecificationValue: Equatable, Sendable {
  public enum Entry: Equatable, Sendable {
    case number(Double)
    case automatic
  }

  public let range: ClosedRange<Double>
  public let step: Double
  public let allowsAutomatic: Bool

  public init(range: ClosedRange<Double>, step: Double, allowsAutomatic: Bool = false) {
    precondition(
      range.lowerBound.isFinite && range.upperBound.isFinite && step.isFinite && step > 0)
    self.range = range
    self.step = step
    self.allowsAutomatic = allowsAutomatic
  }

  public func entry(_ text: String, locale: Locale = .current) -> Entry? {
    if allowsAutomatic && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .automatic
    }
    guard let value = SpecificationNumber.parse(text, locale: locale), range.contains(value) else {
      return nil
    }
    return .number(value)
  }

  public func stepping(_ value: Double, direction: Int, shift: Bool = false, option: Bool = false)
    -> Double
  {
    let increment = step * (shift ? 10 : 1) / (option ? 10 : 1)
    let next = ((value + Double(direction) * increment) * 1_000_000).rounded() / 1_000_000
    return min(range.upperBound, max(range.lowerBound, next))
  }
}
