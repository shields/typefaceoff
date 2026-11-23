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

import AppKit
import TypefaceCore

final class GlyphGuideView: NSView {
  let canvas: GlyphDrawingView

  init(canvas: GlyphDrawingView) {
    self.canvas = canvas
    super.init(frame: .zero)
    setAccessibilityElement(false)
  }

  required init?(coder: NSCoder) { nil }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let figures = canvas.figures
    let pixelScale = window?.backingScaleFactor ?? 2
    let points = figures.map { convert($0.origin, from: canvas) }
    let ends = figures.map {
      convert(CGPoint(x: $0.origin.x + $0.advance, y: $0.origin.y), from: canvas)
    }
    for positions in [points, ends] {
      let guides = GlyphGuide.paired(
        a: figures[0].line == nil ? nil : positions[0].x,
        b: figures[1].line == nil ? nil : positions[1].x, pixelScale: pixelScale
      ).filter { $0.position >= 0 && $0.position <= bounds.width }
      let labels = GlyphGuide.labelPositions(for: guides, width: bounds.width)
      for (index, guide) in guides.enumerated() {
        GlyphRendering.stroke(
          context, from: CGPoint(x: guide.position, y: bounds.height - 30),
          to: CGPoint(x: guide.position, y: max(0, bounds.height - canvas.layout.baseline - 116)))
        for (offset, side) in guide.sides.enumerated() {
          GlyphRendering.label(
            side == .a ? "A" : "B",
            at: CGPoint(x: labels[index] + Double(offset) * 14, y: bounds.height - 24),
            width: 10, color: side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue, bold: true)
        }
      }
    }
    let xHeights = figures.map { figure in
      figure.xHeight.map { Double(convert(CGPoint(x: 0, y: figure.origin.y + $0), from: canvas).y) }
    }
    let guides = GlyphGuide.paired(a: xHeights[0], b: xHeights[1], pixelScale: pixelScale)
    for guide in guides {
      GlyphRendering.stroke(
        context, from: CGPoint(x: 0, y: guide.position),
        to: CGPoint(x: bounds.width, y: guide.position))
    }
    if let guide = guides.last {
      GlyphRendering.label("x-height", at: CGPoint(x: 0, y: guide.position + 3), width: 80)
    }
    let baseline = convert(
      CGPoint(x: 0, y: canvas.bounds.height - canvas.layout.baseline), from: canvas
    ).y
    GlyphRendering.stroke(
      context, from: CGPoint(x: 0, y: baseline), to: CGPoint(x: bounds.width, y: baseline),
      ink: true)
    GlyphRendering.label("baseline", at: CGPoint(x: 0, y: baseline + 3), width: 80)
  }
}
