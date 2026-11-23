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

import Foundation

@testable import UIFuzzSupport

/// An unscoped lookup over the fake tree that the scoped resolver is checked against.
struct LegacyResolver {
  let application: FakeNode

  func names(of element: FakeNode) -> Set<String> {
    element.fakeAttributes.names
  }

  func requireTarget(_ target: String?) -> FakeNode? {
    guard let target else { return nil }
    return firstDescendant(of: application, matching: { names(of: $0).contains(target) })
  }

  func require(_ action: FuzzAction) -> FakeNode? {
    guard let path = action.targetPath else { return requireTarget(action.target) }
    if let element = element(at: path),
      action.targetRole == element.fakeRole,
      action.target.map({ names(of: element).contains($0) }) ?? true
    {
      return element
    }
    if let target = action.target {
      let matches = descendants(of: application).filter {
        $0.fakeRole == action.targetRole && names(of: $0).contains(target)
      }
      if matches.count == 1 { return matches[0] }
    }
    return nil
  }

  func element(at path: [Int]) -> FakeNode? {
    var element = application
    for index in path {
      let elements = element.childNodes
      guard elements.indices.contains(index) else { return nil }
      element = elements[index]
    }
    return element
  }

  func descendants(of root: FakeNode) -> [FakeNode] {
    var pending = [root]
    var result: [FakeNode] = []
    var visited = Set<Int>()
    while let element = pending.popLast(), result.count < 10_000 {
      guard visited.insert(element.identity).inserted else { continue }
      result.append(element)
      pending.append(contentsOf: element.childNodes.reversed())
    }
    return result
  }

  func firstDescendant(of root: FakeNode, matching predicate: (FakeNode) -> Bool) -> FakeNode? {
    var pending = [root]
    var visited = Set<Int>()
    while let element = pending.popLast(), visited.count < 10_000 {
      guard visited.insert(element.identity).inserted else { continue }
      if predicate(element) { return element }
      pending.append(contentsOf: element.childNodes.reversed())
    }
    return nil
  }
}
