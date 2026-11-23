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

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct DifferenceStripTests {
  @Test func wheelsFollowTheirDominantAxisAndClampToTheStrip() throws {
    let scroll = DifferenceStripView()
    scroll.frame = NSRect(x: 0, y: 0, width: 480, height: 76)
    scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 2400, height: 76))
    scroll.layoutSubtreeIfNeeded()
    for (x, y, precise) in [(0, -3, false), (0, -30, true), (-50, 2, true)] {
      let event = try #require(
        CGEvent(
          scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2,
          wheel1: Int32(y), wheel2: Int32(x), wheel3: 0))
      let before = scroll.contentView.bounds.minX
      scroll.scrollWheel(with: try #require(NSEvent(cgEvent: event)))
      #expect(scroll.contentView.bounds.minX > before)
      #expect(scroll.contentView.bounds.minY == 0)
    }
    scroll.follow(20)
    #expect(abs(scroll.documentVisibleRect.maxX - (21 * 48 + 72)) < 0.001)
    scroll.follow(49)
    #expect(scroll.documentView!.visibleRect.maxX == 2400)
    scroll.follow(49)
    scroll.follow(0)
    #expect(scroll.contentView.bounds.minX == 0)
    scroll.follow(nil)
    scroll.tile()
    #expect(scroll.contentView.bounds.minX == 0)
  }

  @Test func arrowsNavigateFromOneFocusableStripAndSelectionFollows() async throws {
    var directions: [Int] = []
    let host = WorkbenchTestHost(
      DifferenceStrip(count: 50, selection: nil, navigate: { directions.append($0) }) {
        Text("Index test").frame(width: 2400, height: 76)
      }, width: 480, height: 76)
    defer { host.window.close() }
    try await host.settle()
    let scroll = try #require(host.subviews.compactMap { $0 as? DifferenceStripView }.first)
    #expect(scroll.acceptsFirstResponder)
    #expect(host.window.makeFirstResponder(scroll))
    for (code, characters) in [(123, "\u{F702}"), (124, "\u{F703}"), (53, "\u{1b}")] {
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: host.window.windowNumber, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code)))
      scroll.keyDown(with: event)
    }
    #expect(directions == [-1, 1])
    host.setContent(
      DifferenceStrip(count: 50, selection: 49, navigate: { directions.append($0) }) {
        Text("Index test").frame(width: 2400, height: 76)
      })
    try await host.settle()
    #expect(abs(scroll.documentVisibleRect.maxX - (2400 + 72)) < 0.001)
    scroll.setFrameSize(NSSize(width: 240, height: 76))
    scroll.tile()
    #expect(abs(scroll.documentVisibleRect.maxX - (2400 + 72)) < 0.001)
  }
}
