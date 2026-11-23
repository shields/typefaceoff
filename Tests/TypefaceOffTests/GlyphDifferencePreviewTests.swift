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
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct GlyphDifferencePreviewTests {
  @Test func overlaysShowSharedInkAndBothFontsDifferences() throws {
    let view = GlyphDifferenceDrawingView(frame: NSRect(x: 0, y: 0, width: 46, height: 38))
    view.draw(.zero)
    let a = FontConfiguration("HelveticaNeue")
    view.preview = GlyphDifferencePreview(glyph: "g", a: a, b: a, spacingOnly: false)
    let shared = try colors(view)
    #expect(shared.contains { $0.redComponent < 0.3 })
    #expect(shared.allSatisfy { abs($0.redComponent - $0.blueComponent) < 0.03 })

    var b = FontConfiguration("Georgia")
    view.preview = GlyphDifferencePreview(glyph: "g", a: a, b: b, spacingOnly: false)
    let overlay = try colors(view)
    #expect(overlay.contains { $0.redComponent - $0.blueComponent > 0.2 })
    #expect(overlay.contains { $0.blueComponent - $0.redComponent > 0.2 })
    #expect(overlay.contains { max($0.redComponent, $0.greenComponent, $0.blueComponent) < 0.3 })

    b.size *= 1.5
    view.preview = GlyphDifferencePreview(glyph: "g", a: a, b: b, spacingOnly: false)
    let resized = try colors(view)
    #expect(resized != overlay)
    b.tracking = 0.25
    view.preview = GlyphDifferencePreview(glyph: "g", a: a, b: b, spacingOnly: true)
    #expect(try colors(view) != resized)
  }

  @Test func unavailableFontsAndCharactersShowTheSameVisiblePlaceholder() throws {
    let view = GlyphDifferenceDrawingView(frame: NSRect(x: 0, y: 0, width: 46, height: 38))
    let a = FontConfiguration("HelveticaNeue")
    view.preview = GlyphDifferencePreview(
      glyph: "g", a: a, b: .init("TypefaceOff-Does-Not-Exist"), spacingOnly: false)
    let missingFont = try colors(view)
    #expect(missingFont.contains { $0.redComponent < 0.5 })
    view.preview = GlyphDifferencePreview(glyph: "🦄", a: a, b: a, spacingOnly: false)
    #expect(try colors(view) == missingFont)
  }

  private func colors(_ view: NSView) throws -> [NSColor] {
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return try (0..<bitmap.pixelsHigh).flatMap { y in
      try (0..<bitmap.pixelsWide).map { x in
        try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
      }
    }
  }
}
