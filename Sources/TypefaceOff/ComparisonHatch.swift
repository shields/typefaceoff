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

struct ComparisonHatch {
  let rising: Bool
  var scale: CGFloat = 1

  func draw(in context: CGContext, rect: CGRect) {
    guard !rect.isEmpty else { return }
    context.saveGState()
    context.clip(to: rect)
    context.setStrokeColor(CGColor(red: 251 / 255, green: 252 / 255, blue: 253 / 255, alpha: 1))
    context.setLineWidth(1.5 / scale)
    let step = 6 / scale
    let direction: CGFloat = rising ? 1 : -1
    let minimum = rect.minX - max(direction * rect.minY, direction * rect.maxY)
    let maximum = rect.maxX - min(direction * rect.minY, direction * rect.maxY)
    for offset in stride(from: floor(minimum / step) * step, through: maximum, by: step) {
      context.move(to: CGPoint(x: offset + direction * rect.minY, y: rect.minY))
      context.addLine(to: CGPoint(x: offset + direction * rect.maxY, y: rect.maxY))
    }
    context.strokePath()
    context.restoreGState()
  }
}
