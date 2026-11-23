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
import CoreText
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct MatchModeTests {
  @Test(arguments: [960.0, 1440])
  func livePreviewKeepsNavigationAndTheAppliedIndexAvailable(width: Double) async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let (stream, continuation) = AsyncThrowingStream<FontFitResult, Error>.makeStream()
    let fit = FontFitModel { _, _ in stream }
    let host = WorkbenchTestHost(WorkbenchView(model: model, fit: fit), width: width)
    defer {
      host.window.close()
      continuation.finish()
    }
    try await host.settle()
    let strip = try #require(host.subviews.compactMap { $0 as? DifferenceStripView }.first)
    let originalY = strip.convert(strip.bounds, to: host.view).minY
    try await host.press("Match…")
    try await host.settle()
    #expect(host.window.sheets.isEmpty)
    #expect(abs(abs(strip.convert(strip.bounds, to: host.view).minY - originalY) - 76) < 0.5)
    let fields = host.subviews.compactMap { $0 as? SpecificationFieldView }
    #expect(fields.allSatisfy { !$0.field.isEnabled })
    for name in ["Font A family", "Font B family", "Toggle comparison inspector"] {
      #expect(!host.isEnabled(name))
    }
    let modes = try #require(host.subviews.compactMap { $0 as? NSSegmentedControl }.first)
    #expect(modes.isEnabled(forSegment: 0) && modes.isEnabled(forSegment: 1))
    #expect(!modes.isEnabled(forSegment: 2))
    try await host.press("Font B Optimize size")
    var proposal = try #require(initial.b)
    proposal.size = 21.46
    continuation.yield(
      .init(
        proposed: proposal, originalScore: SimilarityModelTests.score(0.203),
        score: SimilarityModelTests.score(0.187), evaluations: 412, finished: false))
    try await host.settle {
      fields.first { $0.field.accessibilityIdentifier() == "Font B Size field" }?
        .field.stringValue == "21.46"
    }
    #expect(model.comparison == initial)
    #expect(fit.running && !host.isEnabled("Apply"))
    try capture(host, name: "running", width: width)
    modes.selectedSegment = 1
    modes.sendAction(modes.action!, to: modes.target)
    try await host.settle { model.comparison.mode == .glyph }
    #expect(fit.running && fit.result?.proposed == proposal)
    let search = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
    try await host.submit("U+0042", to: search)
    try await host.settle { model.comparison.selectedGlyph == "B" }
    #expect(fit.running && fit.result?.proposed == proposal)
    modes.selectedSegment = 0
    modes.sendAction(modes.action!, to: modes.target)
    try await host.press("Stop")
    try await host.settle { host.isEnabled("Apply") }
    try capture(host, name: "stopped", width: width)
    let preview = try #require(
      host.subviews.compactMap { $0 as? SpecimenNSTextView }.first {
        $0.accessibilityLabel() == "Font B specimen"
      })
    let font = try #require(
      preview.textStorage?.attribute(.font, at: preview.bodyRange.location, effectiveRange: nil)
        as? NSFont)
    #expect(abs(font.pointSize - proposal.size) < 0.001)
    try await host.press("Cancel matching")
    try await host.settle { fit.result == nil }
    #expect(model.comparison.a == initial.a && model.comparison.b == initial.b)
    #expect(abs(strip.convert(strip.bounds, to: host.view).minY - originalY) < 0.5)
  }

  @Test func openingMatchFromLanguagesUsesTextAndUndoClosesThePreview() async throws {
    let model = WorkbenchModel()
    let fit = FontFitModel(load: SimilarityModelTests.fitResult)
    let host = WorkbenchTestHost(WorkbenchView(model: model, fit: fit))
    defer { host.window.close() }
    model.edit("Adjust B", undoManager: host.window.undoManager) { $0.b?.size = 24 }
    model.updatePresentation { $0.mode = .languages }
    try await host.settle()
    try await host.press("Match…")
    try await host.settle { model.comparison.mode == .text }
    try await host.press("Font B Optimize size")
    try await host.settle { fit.result != nil && !fit.running }
    host.window.undoManager?.undo()
    try await host.settle { fit.result == nil }
    #expect(model.comparison.b?.size == 22)
  }

  @Test func changingTheExactSampleClosesMatch() async throws {
    var comparison = Comparison()
    comparison.sample = .custom
    comparison.customText = "é"
    let model = WorkbenchModel(comparison: comparison)
    let fit = FontFitModel(load: SimilarityModelTests.fitResult)
    let host = WorkbenchTestHost(WorkbenchView(model: model, fit: fit, matching: true))
    defer { host.window.close() }
    try await host.press("Font B Optimize tracking")
    try await host.settle { fit.result != nil && !fit.running }
    model.comparison.customText = "e\u{301}"
    try await host.settle { fit.result == nil }
    #expect(!fit.running)
  }

  @Test func aSingleAxisOptimizesDirectlyAndTheOpenInspectorShowsTheLockedPreview() async throws {
    let url = try #require(
      Bundle(for: MatchFixtureBundle.self).url(forResource: "Weight", withExtension: "ttf"))
    try #require(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
    defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
    let config = FontConfiguration("TypefaceOffMatchWeight-Regular")
    let axis = try #require(config.face.axes.first)
    #expect(config.face.axes.count == 1)
    var comparison = Comparison(a: config, b: config)
    comparison.sample = .custom
    comparison.customText = "a"
    let model = WorkbenchModel(comparison: comparison, catalog: FontCatalog())
    let fit = FontFitModel(load: SimilarityModelTests.fitResult)
    let host = WorkbenchTestHost(WorkbenchView(model: model, fit: fit))
    defer { host.window.close() }
    try await host.press("Show Inspector")
    try await host.settle()
    try await host.press("Match…")
    try await host.press("Font B Optimize axis \(axis.id)")
    try await host.settle { fit.result != nil && host.isEnabled("Apply") }
    let fields = host.subviews.compactMap { $0 as? SpecificationFieldView }
    let field = try #require(
      fields.first {
        $0.field.accessibilityIdentifier() == "Font B Inspector Weight field"
      })
    #expect(field.field.stringValue == "400.1")
    #expect(fields.allSatisfy { !$0.field.isEnabled })
    #expect(host.subviews.compactMap { $0 as? NSSlider }.allSatisfy { !$0.isEnabled })
    #expect(model.comparison == comparison)
    try await host.press("Apply")
    #expect(model.comparison.a == config)
    #expect(model.comparison.b?.axes[axis.id] == 400.1)
  }

  @Test(arguments: [1, 2])
  func compactTypographyReportsPreviousChanges(count: Int) async throws {
    let url = try #require(
      Bundle(for: MatchFixtureBundle.self).url(forResource: "Weight", withExtension: "ttf"))
    try #require(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
    defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
    var config = FontConfiguration("TypefaceOffMatchWeight-Regular")
    let features = config.face.features.filter {
      !$0.isAutomatic && $0.options.contains { $0.value == 0 }
        && $0.defaultValue != 0
    }
    try #require(features.count >= 2)
    for feature in features.prefix(count) { config.features[feature.id] = 0 }
    var comparison = Comparison(a: config, b: config)
    comparison.sample = .custom
    comparison.customText = "a"
    let model = WorkbenchModel(comparison: comparison, catalog: FontCatalog())
    let fit = FontFitModel { request, candidate in
      var proposal = candidate
      for feature in request.b.face.features where request.options.features.contains(feature.id) {
        proposal.features[feature.id] = feature.defaultValue
      }
      return AsyncThrowingStream {
        $0.yield(
          .init(
            proposed: proposal, originalScore: SimilarityModelTests.score(0.5),
            score: SimilarityModelTests.score(0.4), evaluations: 1, finished: true))
        $0.finish()
      }
    }
    let host = WorkbenchTestHost(WorkbenchView(model: model, fit: fit, matching: true), width: 960)
    defer { host.window.close() }
    let feature = features[0]
    try await host.choose(
      "Font B Optimize typography", nativeTitles: [feature.name], item: feature.name)
    try await host.settle { host.isEnabled("Apply") }
    let previous = try await host.element("Font B previous typography")
    let text: String? = previous.accessibilityValue?()
    #expect(text == "was \(count) \(count == 1 ? "change" : "changes")")
    #expect(model.comparison == comparison)
    try await host.press("Apply")
    #expect(model.comparison.b?.features[feature.id] == feature.defaultValue)
    #expect(model.comparison.a == comparison.a)
  }

  @Test func staleMatchControlsCannotReopenMatchAfterBIsRemoved() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(WorkbenchView(model: model))
    defer { host.window.close() }
    let match = try await host.element("Match…")
    model.comparison.b = nil
    _ = match.accessibilityPerformPress?()
    try await host.settle()
    #expect(model.comparison.b == nil && host.window.sheets.isEmpty)
  }

  @Test func headerCanFinishRenderingAProposalAfterBIsRemoved() async throws {
    let model = WorkbenchModel()
    let proposal = try #require(model.comparison.b)
    let host = WorkbenchTestHost(
      SpecificationHeader(
        model: model, inspectorOpen: false, matching: true, preview: proposal,
        openInspector: { _ in }, match: {}), height: 182)
    defer { host.window.close() }
    try await host.settle()
    model.comparison.b = nil
    try await host.settle()
    let field = try #require(
      host.subviews.compactMap { $0 as? SpecificationFieldView }.first {
        $0.field.accessibilityIdentifier() == "Font B Size field"
      })
    #expect(!field.field.isEnabled && field.field.stringValue == "22")
  }

  private func capture<Content>(
    _ host: WorkbenchTestHost<Content>, name: String, width: Double
  ) throws {
    guard let folder = ProcessInfo.processInfo.environment["TYPEFACEOFF_HEADER_REVIEW"] else {
      return
    }
    let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:])).write(
      to: URL(fileURLWithPath: folder).appendingPathComponent("match-\(name)-\(Int(width)).png"))
  }
}

private final class MatchFixtureBundle: NSObject {}
