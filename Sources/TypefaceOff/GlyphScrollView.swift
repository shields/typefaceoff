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

/// Keep the fitted document geometry independent of the viewport's magnification.
final class GlyphScrollView: NSScrollView {
  let canvas = GlyphDrawingView()
  private(set) lazy var annotations = GlyphGuideView(canvas: canvas)
  var zoomChanged: (Double) -> Void = { _ in }

  convenience init() {
    self.init(frame: .zero)
    borderType = .noBorder
    backgroundColor = NSColor(WorkbenchStyle.paper)
    hasHorizontalScroller = true
    hasVerticalScroller = true
    autohidesScrollers = true
    scrollerStyle = .overlay
    usesPredominantAxisScrolling = false
    horizontalScrollElasticity = .none
    verticalScrollElasticity = .none
    allowsMagnification = true
    minMagnification = 1
    maxMagnification = 8
    documentView = canvas
    addSubview(annotations)
    setAccessibilityIdentifier("Glyph canvas scroll area")
  }

  override func tile() {
    super.tile()
    // contentSize is in viewport points, even when the clip bounds are magnified.
    // Only a real window resize should change the fitted layout and baseline.
    if canvas.frame.size != contentSize {
      canvas.setFrameSize(contentSize)
    }
    annotations.frame = bounds
    annotations.needsDisplay = true
  }

  override func reflectScrolledClipView(_ clipView: NSClipView) {
    super.reflectScrolledClipView(clipView)
    annotations.needsDisplay = true
  }

  func setZoom(_ value: Double, at point: NSPoint? = nil) {
    // Roundoff after reciprocal wheel steps must still return to the fitted view.
    let zoom = value <= minMagnification + 1e-9 ? minMagnification : min(maxMagnification, value)
    guard zoom != magnification else { return }
    let anchor = point ?? NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    setMagnification(zoom, centeredAt: anchor)
    if zoom == minMagnification {
      // AppKit's centering can leave roundoff in the fitted view's origin.
      contentView.scroll(to: .zero)
      reflectScrolledClipView(contentView)
    }
    canvas.needsDisplay = true
    annotations.needsDisplay = true
    window?.invalidateCursorRects(for: canvas)
  }

  func pan(by delta: NSSize) {
    let proposed = contentView.bounds.offsetBy(
      dx: delta.width / magnification, dy: delta.height / magnification)
    contentView.scroll(to: contentView.constrainBoundsRect(proposed).origin)
    reflectScrolledClipView(contentView)
    flashScrollers()
  }

  override func scrollWheel(with event: NSEvent) {
    if event.hasPreciseScrollingDeltas {
      // Gesture and momentum deltas are viewport points, independent of zoom.
      pan(by: NSSize(width: -event.scrollingDeltaX, height: event.scrollingDeltaY))
    } else {
      let delta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
      setZoom(
        magnification * pow(1.1, delta), at: contentView.convert(event.locationInWindow, from: nil))
      zoomChanged(magnification)
    }
  }

  override func magnify(with event: NSEvent) {
    setZoom(
      magnification * (1 + event.magnification),
      at: contentView.convert(event.locationInWindow, from: nil))
    zoomChanged(magnification)
  }

  override func smartMagnify(with event: NSEvent) {
    setZoom(
      magnification > 1 ? 1 : 2,
      at: contentView.convert(event.locationInWindow, from: nil))
    zoomChanged(magnification)
  }
}
