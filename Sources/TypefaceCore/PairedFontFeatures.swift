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
