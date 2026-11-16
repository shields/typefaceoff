@propertyWrapper
public struct ExactText: Equatable, Sendable {
  public var wrappedValue: String

  public init(wrappedValue: String) { self.wrappedValue = wrappedValue }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.wrappedValue.unicodeScalars.elementsEqual(rhs.wrappedValue.unicodeScalars)
  }
}
