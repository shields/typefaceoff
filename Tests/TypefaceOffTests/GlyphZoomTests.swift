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
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct GlyphZoomTests {
  @Test func magnificationKeepsTheFittedCanvasAndPointerAnchorFixed() throws {
    let scroll = makeScroll()
    let frame = scroll.canvas.frame
    let anchor = NSPoint(x: 230, y: 180)
    let screenPoint = scroll.canvas.convert(anchor, to: scroll)
    scroll.setZoom(4, at: anchor)
    scroll.layoutSubtreeIfNeeded()
    #expect(scroll.magnification == 4)
    #expect(scroll.canvas.frame == frame)
    let zoomedPoint = scroll.canvas.convert(anchor, to: scroll)
    #expect(abs(zoomedPoint.x - screenPoint.x) < 1)
    #expect(abs(zoomedPoint.y - screenPoint.y) < 1)
    #expect(abs(scroll.contentView.bounds.width * 4 - scroll.contentSize.width) < 1)
    scroll.setZoom(100)
    #expect(scroll.magnification == 8)
    scroll.setZoom(0)
    #expect(scroll.magnification == 1)
    #expect(scroll.contentView.bounds.origin == .zero)
    scroll.setZoom(1)
    scroll.setFrameSize(NSSize(width: 500, height: 300))
    scroll.layoutSubtreeIfNeeded()
    #expect(scroll.canvas.frame.size == scroll.contentSize)
    #expect(scroll.canvas.frame.size != frame.size)
  }

  @Test func mouseWheelZoomsWhilePreciseScrollingPansBothAxes() throws {
    let scroll = makeScroll()
    var reportedZoom = 1.0
    scroll.zoomChanged = { reportedZoom = $0 }
    let wheel = try scrollEvent(precise: false, x: 0, y: 3)
    #expect(!wheel.hasPreciseScrollingDeltas)
    scroll.canvas.scrollWheel(with: wheel)
    #expect(
      scroll.magnification > 1,
      "wheel delta \(wheel.scrollingDeltaY), inverted \(wheel.isDirectionInvertedFromDevice)")
    #expect(reportedZoom == Double(scroll.magnification))
    scroll.scrollWheel(with: try scrollEvent(precise: false, x: 0, y: -3))
    #expect(scroll.magnification == 1)
    scroll.setZoom(3)
    let original = scroll.contentView.bounds.origin
    let trackpad = try scrollEvent(precise: true, x: 30, y: 40)
    #expect(trackpad.hasPreciseScrollingDeltas)
    #expect(scroll.horizontalScroller?.isEnabled == true)
    #expect(scroll.verticalScroller?.isEnabled == true)
    scroll.scrollWheel(with: trackpad)
    #expect(scroll.magnification == 3)
    #expect(abs(scroll.contentView.bounds.origin.x - (original.x - 10)) < 1)
    #expect(abs(scroll.contentView.bounds.origin.y - (original.y + 40.0 / 3)) < 1)
    let momentum = try scrollEvent(precise: true, x: 30, y: 40, momentum: true)
    #expect(momentum.momentumPhase == .changed)
    scroll.scrollWheel(with: momentum)
    #expect(scroll.magnification == 3)
    #expect(abs(scroll.contentView.bounds.origin.x - (original.x - 20)) < 1)
    scroll.scrollWheel(with: try scrollEvent(precise: true, x: 10_000, y: -10_000))
    #expect(scroll.contentView.bounds.origin == .zero)
  }

  @Test func pinchAndSmartZoomShareTheSameLimitsAndCallbacks() {
    let scroll = makeScroll()
    var reportedZoom = 1.0
    scroll.zoomChanged = { reportedZoom = $0 }
    let gesture = GlyphMagnifyEvent()
    gesture.amount = 0.5
    scroll.magnify(with: gesture)
    #expect(scroll.magnification == 1.5)
    #expect(reportedZoom == 1.5)
    gesture.amount = -10
    scroll.magnify(with: gesture)
    #expect(reportedZoom == 1)
    scroll.smartMagnify(with: gesture)
    #expect(reportedZoom == 2)
    scroll.smartMagnify(with: gesture)
    #expect(reportedZoom == 1)
  }

  @Test func draggingPansWithoutReturningToTextAndStopsOnMouseUp() throws {
    let scroll = makeScroll()
    let canvas = scroll.canvas
    var returnedToText = false
    canvas.showText = { returnedToText = true }
    scroll.setZoom(2)
    #expect(canvas.accessibilityPerformPress())
    #expect(!returnedToText)
    canvas.resetCursorRects()
    let original = scroll.contentView.bounds.origin
    canvas.mouseDown(with: try mouseEvent(.leftMouseDown, x: 200, y: 150))
    canvas.mouseDragged(with: try mouseEvent(.leftMouseDragged, x: 240, y: 180))
    let panned = scroll.contentView.bounds.origin
    #expect(abs(panned.x - (original.x - 20)) < 1)
    #expect(abs(panned.y - (original.y - 15)) < 1)
    #expect(!returnedToText)
    canvas.mouseUp(with: try mouseEvent(.leftMouseUp, x: 240, y: 180))
    canvas.mouseDragged(with: try mouseEvent(.leftMouseDragged, x: 260, y: 200))
    #expect(scroll.contentView.bounds.origin == panned)
    canvas.mouseDown(with: try mouseEvent(.leftMouseDown, x: 200, y: 150))
    canvas.mouseDragged(with: try mouseEvent(.leftMouseDragged, x: 10_000, y: 10_000))
    #expect(scroll.contentView.bounds.origin == .zero)
    canvas.mouseUp(with: try mouseEvent(.leftMouseUp, x: 10_000, y: 10_000))
    scroll.setZoom(1)
    canvas.resetCursorRects()
    canvas.mouseDown(with: try mouseEvent(.leftMouseDown, x: 200, y: 150))
    #expect(returnedToText)
  }

  @Test func zoomControlsAndNavigationPreserveFontSettingsAndViewport() async throws {
    var comparison = Comparison()
    comparison.mode = .glyph
    let model = WorkbenchModel(comparison: comparison)
    let host = WorkbenchTestHost(WorkbenchView(model: model), width: 1280, height: 800)
    defer { host.window.close() }
    try await host.settle()
    let scroll = try #require(host.subviews.compactMap { $0 as? GlyphScrollView }.first)
    #expect(scroll.magnification == 1)
    #expect(try await host.element("Zoom out").isAccessibilityEnabled?() == false)
    try await host.press("Zoom in")
    try await host.settle()
    #expect(scroll.magnification == 1.25)
    try await host.press("Zoom out")
    try await host.settle()
    #expect(scroll.magnification == 1)
    try await host.press("Zoom in")
    try await host.settle()
    #expect(scroll.magnification > 1)
    scroll.magnify(with: GlyphMagnifyEvent())
    try await host.settle()
    let zoom = scroll.magnification
    let bounds = scroll.contentView.bounds
    let frame = scroll.canvas.frame
    let right = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: host.window.windowNumber, context: nil, characters: "\u{F703}",
        charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124))
    scroll.canvas.keyDown(with: right)
    try await host.settle()
    #expect(model.comparison.selectedGlyph != comparison.selectedGlyph)
    #expect(scroll.magnification == zoom)
    #expect(scroll.contentView.bounds == bounds)
    #expect(scroll.canvas.frame == frame)
    #expect(model.comparison.a == comparison.a)
    #expect(model.comparison.b == comparison.b)
    #expect(model.comparison.link == comparison.link)
    #expect(host.window.undoManager?.canUndo == false)
    try await host.press("Reset glyph zoom")
    try await host.settle()
    #expect(scroll.magnification == 1)
    #expect(scroll.contentView.bounds.origin == .zero)
  }

  @Test func zoomedOverlayRendersAcrossTheViewport() throws {
    let scroll = makeScroll()
    scroll.canvas.update(Comparison())
    scroll.setZoom(8)
    for x in [0.0, 260.0, 560.0] {
      scroll.contentView.scroll(to: NSPoint(x: x, y: 80))
      scroll.reflectScrolledClipView(scroll.contentView)
      let rect = scroll.canvas.visibleRect
      let bitmap = try #require(scroll.canvas.bitmapImageRepForCachingDisplay(in: rect))
      scroll.canvas.cacheDisplay(in: rect, to: bitmap)
      #expect(bitmap.pixelsWide > 0)
    }
  }

  private func makeScroll() -> GlyphScrollView {
    _ = NSApplication.shared
    let scroll = GlyphScrollView()
    scroll.setFrameSize(NSSize(width: 640, height: 400))
    scroll.layoutSubtreeIfNeeded()
    return scroll
  }

  private func scrollEvent(precise: Bool, x: Int32, y: Int32, momentum: Bool = false) throws
    -> NSEvent
  {
    let event = try #require(
      CGEvent(
        scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2,
        wheel1: y, wheel2: x, wheel3: 0))
    event.location = CGPoint(x: 320, y: 200)
    event.timestamp = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    if momentum {
      event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
    }
    return try #require(NSEvent(cgEvent: event))
  }

  private func mouseEvent(_ type: NSEvent.EventType, x: Double, y: Double) throws -> NSEvent {
    try #require(
      NSEvent.mouseEvent(
        with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
  }
}

private final class GlyphMagnifyEvent: NSEvent {
  var amount = 0.5
  override var magnification: CGFloat { amount }
  override var locationInWindow: NSPoint { NSPoint(x: 320, y: 200) }
}
