import Foundation

public enum ResolutionSignature {
  public static let missing = "Control not found: "
  public static let ambiguous = "Ambiguous control: "
  public static let persistent = "Persistent stale control: "
}

public enum ResolutionMiss: String, Codable, Sendable {
  case noTarget
  case noMatch
  case pathOutsideScope
  /// Reads failed or ran out of time, so the tree may be incomplete. Never skippable.
  case unreadable
}

public struct ResolutionFailure: Error, Equatable, Sendable, CustomStringConvertible {
  public enum Kind: Equatable, Sendable {
    case missing(ResolutionMiss)
    case ambiguous(matches: Int, offered: Int)
  }

  public var kind: Kind
  public var label: String

  public init(kind: Kind, label: String) {
    self.kind = kind
    self.label = label
  }

  public static func missing(_ label: String) -> ResolutionFailure {
    ResolutionFailure(kind: .missing(.noMatch), label: label)
  }

  public var description: String {
    switch kind {
    case .missing: ResolutionSignature.missing + label
    case .ambiguous: ResolutionSignature.ambiguous + label
    }
  }

  /// A clause for the finding detail. Counts stay out of the signature so Minimize still matches.
  public var reason: String {
    switch kind {
    case .missing(.noTarget): "The action names no control"
    case .missing(.noMatch): "No control matched in the scope window"
    case .missing(.pathOutsideScope):
      "The recorded path points into a window that is not the scope window"
    case .missing(.unreadable): "The accessibility tree could not be read completely in time"
    case .ambiguous(let matches, let offered):
      "\(matches) controls have this name and \(offered) of them are offered"
    }
  }

  public var isSkippable: Bool {
    switch kind {
    case .missing(.unreadable): false
    default: true
    }
  }
}
