public struct SpecificationLayout: Equatable, Sendable {
  public let width: Double
  public let compact: Bool
  public let showsTypography: Bool

  public init(width: Double, inspectorOpen: Bool) {
    self.width = width
    compact = width < 1240 || inspectorOpen
    showsTypography = width >= 1120 && !inspectorOpen
  }

  public var style: Double { width * 0.2 + 96 }
  public var size: Double { (width + 64) / 2 }
  public var weight: Double { size + 88 }
  public var leading: Double { size + (compact ? 152 : 160) }
  public var tracking: Double { size + (compact ? 248 : 264) }
  public var typography: Double { size + (compact ? 344 : 400) }
  public var indexControls: Double { compact ? tracking : typography }
  public var familyWidth: Double { style - 80 }
  public var styleWidth: Double { size - style - 32 }
  public var weightFieldWidth: Double { compact ? 58 : 66 }
  public var trackingFieldWidth: Double { compact ? 90 : 122 }
}
