import ApplicationServices
import CoreGraphics
import Foundation
import UIFuzzSupport

/// Equality is `CFEqual`, so a hash collision cannot drop a real element.
struct AXIdentity: Hashable {
  let element: AXUIElement

  static func == (lhs: AXIdentity, rhs: AXIdentity) -> Bool { CFEqual(lhs.element, rhs.element) }

  func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

struct SystemClock: ResolutionClock {
  var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

  func sleep(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
}

final class AXReads {
  var errors = 0
}

/// One element of one capture. Every attribute is read at most once; a new capture builds new nodes.
final class AXNode: AccessibilityNode {
  let element: AXUIElement
  private let reads: AXReads

  init(_ element: AXUIElement, reads: AXReads) {
    self.element = element
    self.reads = reads
  }

  var identity: AXIdentity { AXIdentity(element: element) }
  var readErrors: Int { reads.errors }

  lazy var role: String = string(kAXRoleAttribute)
  lazy var subrole: String = string(kAXSubroleAttribute)
  private lazy var identifier: String = string(kAXIdentifierAttribute)
  private lazy var title: String = string(kAXTitleAttribute)
  private lazy var descriptionText: String = string(kAXDescriptionAttribute)
  private lazy var help: String = string(kAXHelpAttribute)
  lazy var frame: CGRect? = readFrame()

  lazy var attributes = AccessibilityAttributes(
    identifier: identifier, title: title, description: descriptionText, help: help)

  lazy var visibilityInput = VisibilityInput(
    role: role, subrole: subrole, title: role == "AXMenuBarItem" ? title : "", frame: frame,
    isEnabled: read(kAXEnabledAttribute) as? Bool, isHidden: read("AXHidden") as? Bool)

  lazy var children: [AXNode] = (read(kAXChildrenAttribute) as? [AXUIElement] ?? []).map {
    AXNode($0, reads: reads)
  }

  /// The first of identifier, title, and description, reading no more of them than needed.
  var discoveryTarget: String? {
    if !identifier.isEmpty { return identifier }
    if !title.isEmpty { return title }
    return descriptionText.isEmpty ? nil : descriptionText
  }

  func hasName(_ name: String) -> Bool {
    if !name.isEmpty, identifier == name { return true }
    return names.contains(name)
  }

  /// Only meaningful on the application node.
  func focusedWindow() -> AXIdentity? {
    guard let value = read(kAXFocusedWindowAttribute),
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return AXIdentity(element: value as! AXUIElement)
  }

  private func read(_ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    switch AXUIElementCopyAttributeValue(element, name as CFString, &value) {
    case .success: return value
    case .noValue, .attributeUnsupported: return nil
    default:
      reads.errors += 1
      return nil
    }
  }

  private func string(_ name: String) -> String { read(name) as? String ?? "" }

  private func readFrame() -> CGRect? {
    guard let position = read(kAXPositionAttribute), let size = read(kAXSizeAttribute),
      CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
      AXValueGetValue(size as! AXValue, .cgSize, &extent)
    else { return nil }
    return CGRect(origin: origin, size: extent)
  }
}
