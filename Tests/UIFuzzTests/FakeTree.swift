// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CoreGraphics
import Foundation

@testable import UIFuzzSupport

/// A clock whose `sleep` only advances time, in whole microseconds so that comparisons are exact.
final class FakeClock: ResolutionClock {
  private var ticks = 0
  private(set) var sleeps: [TimeInterval] = []

  var now: TimeInterval { Double(ticks) / 1e6 }

  func sleep(_ seconds: TimeInterval) {
    sleeps.append(seconds)
    advance(seconds)
  }

  func advance(_ seconds: TimeInterval) {
    ticks += max(1, Int((seconds * 1e6).rounded()))
  }
}

final class FakeWorld {
  static let windowFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
  static let controlFrame = CGRect(x: 10, y: 10, width: 100, height: 30)

  private var nextIdentity = 0
  private var reads: [Int: [String: Int]] = [:]
  var clock: FakeClock?
  var secondsPerRead = 0.0
  var readErrors = 0
  var focusReads = 0

  func record(_ identity: Int, _ kind: String) {
    reads[identity, default: [:]][kind, default: 0] += 1
    clock?.advance(secondsPerRead)
  }

  func reads(of node: FakeNode, _ kind: String) -> Int {
    reads[node.identity]?[kind] ?? 0
  }

  func node(
    _ role: String, subrole: String = "", name: String = "",
    attributes: AccessibilityAttributes? = nil, frame: CGRect? = FakeWorld.controlFrame,
    enabled: Bool? = nil, hidden: Bool? = nil, children: [FakeNode] = []
  ) -> FakeNode {
    nextIdentity += 1
    return FakeNode(
      world: self, identity: nextIdentity, role: role, subrole: subrole,
      attributes: attributes ?? AccessibilityAttributes(identifier: name), frame: frame,
      isEnabled: enabled, isHidden: hidden, childNodes: children)
  }

  func menuItem(
    _ identifier: String, title: String = "", frame: CGRect? = FakeWorld.controlFrame,
    children: [FakeNode] = []
  ) -> FakeNode {
    node(
      "AXMenuItem", attributes: AccessibilityAttributes(identifier: identifier, title: title),
      frame: frame, children: children)
  }

  func window(name: String = "", children: [FakeNode]) -> FakeNode {
    node(
      "AXWindow", subrole: "AXStandardWindow", name: name, frame: FakeWorld.windowFrame,
      children: children)
  }

  func menuBar(_ titles: [String]) -> FakeNode {
    node(
      "AXMenuBar", frame: nil,
      children: titles.map { title in
        node(
          "AXMenuBarItem", attributes: AccessibilityAttributes(title: title), frame: nil,
          children: [
            node(
              "AXMenu", frame: FakeWorld.windowFrame,
              children: [
                node("AXMenuItem", name: "\(title) item")
              ])
          ])
      })
  }

  func application(_ children: [FakeNode]) -> FakeNode {
    node("AXApplication", frame: nil, children: children)
  }

  func resolver(
    _ application: FakeNode, focused: FakeNode?, nodeLimit: Int = 10_000,
    clock: FakeClock? = nil, budget: TimeInterval = 1_000
  ) -> AccessibilityResolver<FakeNode> {
    AccessibilityResolver(
      application: application,
      focusedWindow: {
        self.focusReads += 1
        return focused?.identity
      }, nodeLimit: nodeLimit, clock: clock ?? self.clock ?? FakeClock(), budgetSeconds: budget)
  }
}

final class FakeNode: AccessibilityNode {
  let world: FakeWorld
  let identity: Int
  let fakeRole: String
  let fakeSubrole: String
  var fakeAttributes: AccessibilityAttributes
  var frame: CGRect?
  var isEnabled: Bool?
  var isHidden: Bool?
  var visibleRows: [FakeNode]?
  var header: FakeNode?
  var childNodes: [FakeNode]
  var failsToReadChildren = false

  init(
    world: FakeWorld, identity: Int, role: String, subrole: String,
    attributes: AccessibilityAttributes, frame: CGRect?, isEnabled: Bool?, isHidden: Bool?,
    childNodes: [FakeNode]
  ) {
    self.world = world
    self.identity = identity
    fakeRole = role
    fakeSubrole = subrole
    fakeAttributes = attributes
    self.frame = frame
    self.isEnabled = isEnabled
    self.isHidden = isHidden
    self.childNodes = childNodes
  }

  var role: String {
    world.record(identity, "role")
    return fakeRole
  }

  var subrole: String {
    world.record(identity, "subrole")
    return fakeSubrole
  }

  var attributes: AccessibilityAttributes {
    world.record(identity, "attributes")
    return fakeAttributes
  }

  var visibilityInput: VisibilityInput {
    world.record(identity, "visibility")
    return VisibilityInput(
      role: fakeRole, subrole: fakeSubrole,
      identifier: fakeRole == "AXMenuItem" ? fakeAttributes.identifier : "",
      title: fakeRole == "AXMenuBarItem" || fakeRole == "AXMenuItem" ? fakeAttributes.title : "",
      frame: frame, isEnabled: isEnabled, isHidden: isHidden)
  }

  var children: [FakeNode] {
    world.record(identity, "children")
    if failsToReadChildren {
      world.readErrors += 1
      return []
    }
    return childNodes
  }

  var readErrors: Int { world.readErrors }

  var subtree: [FakeNode] { [self] + childNodes.flatMap(\.subtree) }
}
