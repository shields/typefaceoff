import CoreGraphics
import Foundation

/// The accessibility tree of the scope window at the moment a control could not be resolved,
/// written to a side file. Nothing reads it back, so it only encodes.
public struct TreeDump: Encodable, Equatable, Sendable {
  public struct Request: Encodable, Equatable, Sendable {
    public var kind: String
    public var target: String?
    public var path: [Int]?
    public var role: String?
    public var label: String
  }

  public struct Scope: Encodable, Equatable, Sendable {
    public var source: WindowScopeSource
    public var standardWindows: Int
    public var selectedIndex: Int?
  }

  public struct TopLevel: Encodable, Equatable, Sendable {
    public var index: Int
    public var role: String
    public var subrole: String
    public var title: String
    public var identifier: String
    public var frame: [Double]?
    public var focused: Bool
    public var inScope: Bool
  }

  public struct Telemetry: Encodable, Equatable, Sendable {
    public var events: Int
    public var pendingWork: Int
    public var openWork: [String: Int]
    public var lastHeartbeatAgeMilliseconds: Int?
    public var lastActivityAgeMilliseconds: Int?
  }

  public struct Entry: Encodable, Equatable, Sendable {
    /// Rooted at the application element, like the paths of recorded actions.
    public var path: [Int]
    public var role: String
    public var subrole: String
    public var identifier: String
    public var title: String
    public var description: String
    public var help: String
    public var frame: [Double]?
    public var enabled: Bool?
    public var hidden: Bool?
    public var offered: Bool
    /// What discovery would have recorded as the node's target.
    public var target: String?

    var attributes: AccessibilityAttributes {
      AccessibilityAttributes(
        identifier: identifier, title: title, description: description, help: help)
    }

    var displayName: String { target ?? attributes.names.sorted().first ?? "" }

    var summary: String? {
      guard let name = attributes.names.sorted().first else { return nil }
      return "\(role.isEmpty ? "?" : role):\(name)"
    }
  }

  public struct Context: Sendable {
    public var action: Int
    public var request: ResolutionRequest
    public var kind: FuzzAction.Kind
    public var error: String
    public var attempts: Int
    public var elapsedMilliseconds: Int
    public var telemetry: TelemetrySummary

    public init(
      action: Int, request: ResolutionRequest, kind: FuzzAction.Kind, error: String,
      attempts: Int, elapsedMilliseconds: Int, telemetry: TelemetrySummary
    ) {
      self.action = action
      self.request = request
      self.kind = kind
      self.error = error
      self.attempts = attempts
      self.elapsedMilliseconds = elapsedMilliseconds
      self.telemetry = telemetry
    }
  }

  public static let entryLimit = 10_000
  public static let budgetSeconds: TimeInterval = 5

  public var version = 1
  public var action: Int
  public var request: Request
  public var error: String
  public var attempts: Int
  public var elapsedMilliseconds: Int
  public var scope: Scope
  public var topLevel: [TopLevel]
  public var telemetry: Telemetry
  /// Reads that failed for a reason other than "no value", so the tree may be incomplete.
  public var readErrors: Int
  public var truncated: Bool
  /// `limit` or `time`.
  public var truncatedReason: String?
  public var entries: [Entry]

  public func candidates(for request: ResolutionRequest) -> [Entry] {
    guard let target = request.target else { return [] }
    return entries.filter { $0.role == request.role && $0.attributes.names.contains(target) }
  }

  public func visibleElements(limit: Int = 100) -> [String] {
    Array(entries.lazy.compactMap(\.summary).prefix(limit))
  }
}

extension TreeDump {
  /// Walks the scope window and the menu bar without pruning, and marks what discovery would have
  /// offered. Stops at `entryLimit` nodes or after `budgetSeconds` on `clock`, and says which.
  public static func capture<Node: AccessibilityNode>(
    _ context: Context, application: Node, focusedWindow: () -> Node.Identity?,
    clock: some ResolutionClock, budgetSeconds: TimeInterval = TreeDump.budgetSeconds,
    entryLimit: Int = TreeDump.entryLimit
  ) -> TreeDump {
    let started = clock.now
    let roots = application.children
    let children = roots.map {
      TopLevelChild(identity: $0.identity, role: $0.role, subrole: $0.subrole)
    }
    let focused = focusedWindow()
    let scope = WindowScope(children: children, focused: focused)
    let topLevel = roots.indices.map { index in
      let root = roots[index]
      let input = root.visibilityInput
      let attributes = root.attributes
      return TopLevel(
        index: index, role: input.role, subrole: input.subrole, title: attributes.title,
        identifier: attributes.identifier, frame: input.frame.map(Self.array),
        focused: focused == root.identity,
        inScope: scope.includes(index: index, child: children[index]))
    }
    var pending: [(node: Node, path: [Int], clip: CGRect?, live: Bool)] = roots.indices.reversed()
      .filter { topLevel[$0].inScope }
      .map { (roots[$0], [$0], nil, true) }
    var seen = Set<Node.Identity>()
    var entries: [Entry] = []
    var traversed: [ModalCandidate<Node.Identity>] = []
    var truncatedReason: String?
    while let item = pending.popLast() {
      if entries.count >= entryLimit {
        truncatedReason = "limit"
        break
      }
      if clock.now - started >= budgetSeconds {
        truncatedReason = "time"
        break
      }
      guard seen.insert(item.node.identity).inserted else { continue }
      let input = item.node.visibilityInput
      let attributes = item.node.attributes
      var clip = item.clip
      var live = item.live
      var offered = false
      switch VisibilityRules.disposition(input, parentClip: item.clip) {
      case .prune: live = false
      case .keep(let emits, let next):
        clip = next
        offered = emits && live
        if live {
          traversed.append(
            ModalCandidate(
              identity: item.node.identity, path: item.path, role: input.role, offered: emits))
        }
      }
      entries.append(
        Entry(
          path: item.path, role: input.role, subrole: input.subrole,
          identifier: attributes.identifier, title: attributes.title,
          description: attributes.description, help: attributes.help,
          frame: input.frame.map(Self.array), enabled: input.isEnabled, hidden: input.isHidden,
          offered: offered, target: attributes.discoveryTarget))
      for (index, child) in item.node.children.enumerated().reversed() {
        pending.append((child, item.path + [index], clip, live))
      }
    }
    let modal = ModalScope.selection(scope: scope, focused: focused, traversed: traversed)
    for index in entries.indices where !modal.contains(entries[index].path) {
      entries[index].offered = false
    }
    return TreeDump(
      action: context.action,
      request: Request(
        kind: context.kind.rawValue, target: context.request.target, path: context.request.path,
        role: context.request.role, label: context.request.label),
      error: context.error, attempts: context.attempts,
      elapsedMilliseconds: context.elapsedMilliseconds,
      scope: Scope(
        source: scope.source, standardWindows: scope.standardWindowCount,
        selectedIndex: scope.scopeIndex),
      topLevel: topLevel,
      telemetry: Telemetry(
        events: context.telemetry.events, pendingWork: context.telemetry.pendingWork,
        openWork: context.telemetry.openWorkKinds,
        lastHeartbeatAgeMilliseconds: context.telemetry.lastHeartbeat.map {
          Self.milliseconds(started - $0)
        },
        lastActivityAgeMilliseconds: context.telemetry.lastActivity.map {
          Self.milliseconds(started - $0)
        }),
      readErrors: application.readErrors, truncated: truncatedReason != nil,
      truncatedReason: truncatedReason, entries: entries)
  }

  private static func array(_ frame: CGRect) -> [Double] {
    [frame.origin.x, frame.origin.y, frame.width, frame.height]
  }

  private static func milliseconds(_ seconds: TimeInterval) -> Int {
    Int((seconds * 1000).rounded())
  }
}
