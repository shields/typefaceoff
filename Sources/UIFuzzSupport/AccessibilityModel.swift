import CoreGraphics
import Foundation

public struct VisibilityInput: Equatable, Sendable {
  public var role: String
  public var subrole: String
  /// Filled by adapters only for `AXMenuItem`.
  public var identifier: String
  /// Filled by adapters only for `AXMenuBarItem` and `AXMenuItem`.
  public var title: String
  public var frame: CGRect?
  public var isEnabled: Bool?
  public var isHidden: Bool?

  public init(
    role: String = "", subrole: String = "", identifier: String = "", title: String = "",
    frame: CGRect? = nil, isEnabled: Bool? = nil, isHidden: Bool? = nil
  ) {
    self.role = role
    self.subrole = subrole
    self.identifier = identifier
    self.title = title
    self.frame = frame
    self.isEnabled = isEnabled
    self.isHidden = isHidden
  }
}

public struct AccessibilityAttributes: Equatable, Sendable {
  public var identifier: String
  public var title: String
  public var description: String
  public var help: String

  public init(
    identifier: String = "", title: String = "", description: String = "", help: String = ""
  ) {
    self.identifier = identifier
    self.title = title
    self.description = description
    self.help = help
  }

  public var names: Set<String> {
    Set([identifier, title, description, help].filter { !$0.isEmpty })
  }

  /// What discovery records as an action's target: help is never a target.
  public var discoveryTarget: String? {
    [identifier, title, description].first { !$0.isEmpty }
  }
}

/// A node of the accessibility tree, class-shaped so an adapter can cache reads per capture.
public protocol AccessibilityNode: AnyObject {
  associatedtype Identity: Hashable

  var identity: Identity { get }
  /// `""` when the element has no role, as discovery records it.
  var role: String { get }
  var subrole: String { get }
  var attributes: AccessibilityAttributes { get }
  var visibilityInput: VisibilityInput { get }
  /// In `AXChildren` order.
  var children: [Self] { get }
  var visibleRows: [Self]? { get }
  var header: Self? { get }
  /// Reads that failed for a reason other than "no value" since this capture began. Called on the
  /// application node, so every node of one capture shares the count.
  var readErrors: Int { get }

  var names: Set<String> { get }
  /// Adapters override this to compare the identifier before reading the other names.
  func hasName(_ name: String) -> Bool
}

extension AccessibilityNode {
  public var traversalChildren: [Self] {
    guard let visibleRows else { return children }
    return header.map { [$0] + visibleRows } ?? visibleRows
  }

  public var names: Set<String> { attributes.names }

  public func hasName(_ name: String) -> Bool { names.contains(name) }
}
