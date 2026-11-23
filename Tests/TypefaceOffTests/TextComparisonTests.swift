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

@Suite(.serialized) @MainActor struct TextComparisonTests {
  @Test(arguments: [960.0, 1120, 1440])
  func columnsKeepTheirMeasureAndAlignIndependentFirstBaselines(width: Double) async throws {
    var comparison = Comparison()
    comparison.sample = .custom
    comparison.customText = "A\nA\nA"
    comparison.a.leading = 1
    comparison.b?.size = 26.5
    comparison.b?.leading = 200
    let position = SpecimenScrollPosition()
    let host = WorkbenchTestHost(
      TextComparisonView(
        comparison: comparison, highlights: ["A"], highlightKinds: [:],
        scrollPosition: position, select: { _ in }), width: width, height: 666)
    defer { host.window.close() }
    try await host.settle()
    let views = host.subviews.compactMap { $0 as? SpecimenNSTextView }
    try #require(views.count == 2)
    for (index, view) in views.enumerated() {
      let scroll = try #require(view.enclosingScrollView)
      let frame = scroll.convert(scroll.bounds, to: host.view)
      #expect(abs(frame.width - (width - 192) / 2) < 0.001)
      #expect(abs(frame.minX - (index == 0 ? 64 : (width + 64) / 2)) < 0.001)
      let baselines = SpecimenLeadingTests.baselines(
        try #require(view.layoutManager), range: view.bodyRange)
      try #require(baselines.count == 3)
      #expect(abs(view.textContainerOrigin.y + baselines[0] - 50) < 0.001)
      #expect(abs(baselines[1] - baselines[0] - (index == 0 ? 1 : 200)) < 0.001)
      #expect(view.textContainer?.lineFragmentPadding == 0)
      #expect(view.highlights == ["A"])
      #expect(view.backgroundColor == NSColor(WorkbenchStyle.paper))
    }
    comparison.a.size = 144
    host.setContent(
      TextComparisonView(
        comparison: comparison, highlights: [], highlightKinds: [:],
        scrollPosition: position, select: { _ in }))
    try await host.settle()
    let baselines = try views.map { view in
      let layout = try #require(view.layoutManager)
      let first = try #require(SpecimenLeadingTests.baselines(layout, range: view.bodyRange).first)
      return view.textContainerOrigin.y + first
    }
    #expect(abs(baselines[0] - baselines[1]) < 0.001)
    #expect(baselines[0] > 50)
  }

  @Test func warningsStayVisibleAboveAlignedSpecimenBaselines() async throws {
    var comparison = Comparison(a: .init("HelveticaNeue"), b: .init("ZapfDingbatsITC"))
    comparison.sample = .custom
    comparison.customText = "A\nA"
    let position = SpecimenScrollPosition()
    let makeView = {
      TextComparisonView(
        comparison: comparison, highlights: [], highlightKinds: [:],
        scrollPosition: position, select: { _ in })
    }
    let host = WorkbenchTestHost(makeView())
    defer { host.window.close() }
    for size in [22.0, 144, 22] {
      comparison.a.size = size
      host.setContent(makeView())
      try await host.settle()
      let views = host.subviews.compactMap { $0 as? SpecimenNSTextView }
      try #require(views.count == 2)
      #expect(views[0].bodyRange.location == 0 && views[1].bodyRange.location > 0)
      let baselines = try views.map { view in
        let layout = try #require(view.layoutManager)
        let first = try #require(
          SpecimenLeadingTests.baselines(layout, range: view.bodyRange).first)
        #expect(view.textContainerOrigin.y >= 0)
        return view.textContainerOrigin.y + first
      }
      #expect(abs(baselines[0] - baselines[1]) < 0.001)
      #expect(baselines[0] >= 50)
    }
  }

  @Test func missingFontsStayExplicitAndSuppressUnpairedHighlights() async throws {
    let position = SpecimenScrollPosition()
    var comparison = Comparison(b: nil)
    comparison.sample = .custom
    comparison.customText = "A"
    let makeView = {
      TextComparisonView(
        comparison: comparison, highlights: ["A"], highlightKinds: [:],
        scrollPosition: position, select: { _ in })
    }
    let host = WorkbenchTestHost(makeView())
    defer { host.window.close() }
    for missing in [Side.b, .a] {
      try await host.settle()
      let specimen = try #require(host.subviews.compactMap { $0 as? SpecimenNSTextView }.first)
      #expect(specimen.highlights.isEmpty)
      comparison[missing] = FontConfiguration("TypefaceOff-Does-Not-Exist")
      host.setContent(makeView())
      try await host.settle()
      #expect(
        (host.elements + host.hitElements).contains { element in
          guard element.accessibilityRole?() == .staticText else { return false }
          let value: String? = element.accessibilityValue?()
          return value == "This font is not installed.\nChoose an installed font above."
        })
      #expect(
        host.subviews.compactMap { $0 as? SpecimenNSTextView }.count == (missing == .b ? 1 : 0))
    }
    comparison = Comparison()
    comparison.sample = .custom
    comparison.customText = ""
    host.setContent(makeView())
    try await host.settle()
    #expect(host.subviews.compactMap { $0 as? SpecimenNSTextView }.allSatisfy { $0.string.isEmpty })
  }
}
