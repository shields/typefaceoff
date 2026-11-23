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

public struct GlyphLayout: Sendable {
  public let stageX: Double
  public let stageWidth: Double
  public let baseline: Double
  public let overlaySize: Double
  public let overlayOrigin: Double
  public let soloSize: Double
  public let columnA: Double
  public let columnB: Double
  public let columnWidth: Double

  public init(width: Double, height: Double, ascent: Double, descent: Double) {
    let width = max(960, width)
    stageX = (width + 64) / 2
    stageWidth = width - stageX
    baseline = max(0, min(449, height - 216))
    overlaySize = max(
      0,
      min(
        480, 480 * stageWidth / ((1076 - 64) / 2),
        (baseline - 30) / max(0.01, ascent), 112 / max(0.01, descent)))
    soloSize = overlaySize / (width < 1320 ? 3 : 2)
    overlayOrigin = min(88, max(32, (stageWidth - overlaySize) / 2))
    let tableWidth = min(width < 1320 ? 452 : 540, stageX - 128)
    let labelWidth = width >= 1320 ? 132.0 : tableWidth >= 452 ? 100 : 76
    let gap = width >= 1320 ? 88.0 : min(32, max(8, tableWidth - labelWidth - 320))
    columnWidth = (tableWidth - labelWidth - gap) / 2
    columnA = 64 + labelWidth
    columnB = columnA + columnWidth + gap
  }
}

public struct GlyphGuide: Sendable {
  public let position: Double
  public let sides: [Side]

  public static func paired(a: Double?, b: Double?, pixelScale: Double) -> [Self] {
    let guides = [(Side.a, a), (.b, b)].compactMap { side, position in
      position.map { Self(position: $0, sides: [side]) }
    }.sorted { $0.position < $1.position }
    if guides.count == 2 && guides[1].position - guides[0].position <= 1 / pixelScale {
      return [Self(position: (guides[0].position + guides[1].position) / 2, sides: [.a, .b])]
    }
    return guides
  }

  public static func labelPositions(for guides: [Self], width: Double) -> [Double] {
    let end = max(0, width - 24)
    var positions = guides.enumerated().map { index, guide in
      let labelWidth = guide.sides.count == 2 ? 24.0 : 10
      let left = guides.count == 2 && index == 0 || guide.position + labelWidth + 4 > end
      return min(max(0, guide.position + (left ? -labelWidth - 4 : 4)), max(0, end - labelWidth))
    }
    if positions.count == 2 && positions[1] - positions[0] < 14 {
      positions[0] = max(0, positions[1] - 14)
      positions[1] = max(positions[1], positions[0] + 14)
    }
    return positions
  }
}
