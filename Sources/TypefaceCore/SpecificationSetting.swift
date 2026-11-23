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

public enum SpecificationSetting: Hashable, Sendable {
  case size, leading, tracking
  case axis(UInt32)

  public func value(in config: FontConfiguration) -> Double {
    switch self {
    case .size: config.size
    case .leading: FontRenderer.leading(config)
    case .tracking: config.tracking
    case .axis(let id):
      if id == tagNumber("wght") {
        config.weight
      } else {
        config.axes[id] ?? config.face.axes.first { $0.id == id }!.defaultValue
      }
    }
  }

  public func rules(for config: FontConfiguration) -> SpecificationValue? {
    switch self {
    case .size: .init(range: 10...144, step: 1)
    case .leading: .init(range: FontConfiguration.leadingRange, step: 1, allowsAutomatic: true)
    case .tracking: .init(range: -0.12...0.15, step: 0.001)
    case .axis(let id):
      config.face.axes.first { $0.id == id }.map {
        .init(range: $0.minimum...$0.maximum, step: 1)
      }
    }
  }

  @discardableResult
  public func apply(
    _ entry: SpecificationValue.Entry, to comparison: inout Comparison, side: Side, both: Bool,
    catalog: FontCatalog
  ) -> Bool {
    guard let config = comparison[side], FontRenderer.isAvailable(config) else { return false }
    let other: Side = side == .a ? .b : .a
    let otherInstalled = comparison[other].map { FontRenderer.isAvailable($0) } == true
    let targets = both && otherInstalled ? [side, other] : [side]
    let number: Double? = if case .number(let value) = entry { value } else { nil }
    for target in targets {
      guard let targetConfig = comparison[target], let rules = rules(for: targetConfig),
        number.map({ $0.isFinite && rules.range.contains($0) }) ?? rules.allowsAutomatic
      else { return false }
    }
    let locked = comparison.appearanceLocked
    comparison.appearanceLocked = locked && !both && otherInstalled
    for target in targets {
      switch self {
      case .leading: comparison.setLeading(number, side: target)
      case .size: comparison.set(.size, to: number!, side: target, catalog: catalog)
      case .tracking: comparison.set(.tracking, to: number!, side: target, catalog: catalog)
      case .axis(let id):
        comparison.set(
          id == tagNumber("wght") ? .weight : .axis(id), to: number!, side: target,
          catalog: catalog)
      }
    }
    comparison.appearanceLocked = locked
    if both && otherInstalled { equalizeRelation(in: &comparison) }
    return true
  }

  private func equalizeRelation(in comparison: inout Comparison) {
    switch self {
    case .size: comparison.link?.sizeRatio = 1
    case .leading: comparison.link?.leadingOffset = 0
    case .tracking: comparison.link?.trackingOffset = 0
    case .axis(let id):
      comparison.link?.axisOffsets[id] = 0
      if id == tagNumber("wght") { comparison.link?.weightOffset = 0 }
    }
  }
}
