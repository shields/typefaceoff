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
import Foundation
import SwiftUI
import Synchronization
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct SimilarityModelTests {
  nonisolated static func score(_ value: Double) -> SimilarityScore {
    .init(geometry: value, appearance: value, shapedText: value, metrics: value)
  }

  nonisolated static func fitResult(_ request: FontFitModel.Request, _ candidate: FontConfiguration)
    async throws
    -> AsyncThrowingStream<FontFitResult, Error>
  {
    var config = candidate
    if request.options.tracking { config.tracking = 0.025 }
    if request.options.size { config.size += 2 }
    if request.options.leading { config.leading = 36 }
    for axis in request.options.axes { config.axes[axis] = (config.axes[axis] ?? 0) + 0.1 }
    for feature in request.options.features { config.features[feature] = 0 }
    let improved = config != candidate
    let original = candidate == request.b ? 0.5 : 0.3
    let result = FontFitResult(
      proposed: config, originalScore: score(original),
      score: score(improved ? original - 0.1 : original),
      evaluations: 10, finished: true)
    return AsyncThrowingStream {
      $0.yield(result)
      $0.finish()
    }
  }

  @Test func familyScoresSortWithStableNamesAndUnavailableEntriesLast() async throws {
    let model = FamilySimilarityModel { _, _, _ in
      AsyncThrowingStream {
        $0.yield(.init(family: "Beta", score: Self.score(0.2)))
        $0.yield(.init(family: "Alpha", score: Self.score(0.2)))
        $0.yield(.init(family: "Close", score: Self.score(0.1)))
        $0.yield(.init(family: "Missing", score: nil, unavailableReason: "No coverage"))
        $0.finish()
      }
    }
    let names = ["Pending", "Beta", "Missing", "Close", "Alpha"]
    #expect(model.ordered(names) == names)
    model.sort = .similarity
    await model.update(.init(reference: .init("ArialMT"), scale: 2), catalog: FontCatalog())
    #expect(model.ordered(names) == ["Close", "Alpha", "Beta", "Missing", "Pending"])
    #expect(!model.comparing && model.error == nil)
    await model.update(nil, catalog: FontCatalog())
    #expect(model.results.isEmpty)
  }

  @Test func familyProgressCancellationAndFailureAreVisible() async throws {
    let (stream, continuation) = AsyncThrowingStream<FamilySimilarity, Error>.makeStream()
    let model = FamilySimilarityModel { _, _, _ in stream }
    model.sort = .similarity
    let request = FamilySimilarityModel.Request(reference: .init("ArialMT"), scale: 2)
    let task = Task { await model.update(request, catalog: FontCatalog()) }
    try await waitUntil { model.comparing }
    try await Task.sleep(for: .milliseconds(230))
    continuation.yield(.init(family: "Arial", score: Self.score(0)))
    try await waitUntil { model.results.count == 1 }
    #expect(model.comparing && model.results.count == 1)
    task.cancel()
    await task.value
    #expect(!model.comparing && model.error == nil)
    let failed = FamilySimilarityModel { _, _, _ in throw SimilarityError.renderingFailed }
    failed.sort = .similarity
    await failed.update(request, catalog: FontCatalog())
    #expect(failed.error != nil && !failed.comparing)
  }

  @Test func fitApplyIsOneUndoableBEditAndRejectsStaleInputs() async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let b = try #require(initial.b)
    let request = FontFitModel.Request(
      a: initial.a, b: b, text: initial.text, options: .init(config: b), scale: 2)
    let fit = FontFitModel(load: Self.fitResult)
    #expect(!fit.apply(to: model, undoManager: nil))
    fit.start(request)
    try await waitUntil { !fit.running }
    #expect(fit.result?.improved == true && !fit.running)
    model.comparison.a.size += 1
    #expect(!fit.apply(to: model, undoManager: nil))
    model.comparison = initial
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    #expect(fit.apply(to: model, undoManager: undo))
    undo.endUndoGrouping()
    #expect(model.comparison.a == initial.a && model.comparison.b?.size == b.size)
    #expect(model.comparison.b?.postScriptName == b.postScriptName)
    undo.undo()
    #expect(model.comparison == initial)
    fit.start(request)
    try await waitUntil { !fit.running }
    #expect(fit.result?.evaluations == 20)
    fit.start(nil)
    #expect(fit.result == nil && !fit.running)
  }

  @Test func stoppedFitCannotPublishAndErrorsRemainVisible() async throws {
    let (stream, continuation) = AsyncThrowingStream<FontFitResult, Error>.makeStream()
    let fit = FontFitModel { _, _ in stream }
    let b = FontConfiguration("ArialMT")
    let request = FontFitModel.Request(a: b, b: b, text: "a", options: .init(config: b), scale: 2)
    fit.start(request)
    try await Task.sleep(for: .milliseconds(20))
    fit.stop()
    continuation.yield(
      .init(
        proposed: b, originalScore: Self.score(1), score: Self.score(0), evaluations: 1,
        finished: false))
    continuation.finish()
    try await Task.sleep(for: .milliseconds(20))
    #expect(fit.result == nil && !fit.running)
    let failed = FontFitModel { _, _ in throw SimilarityError.renderingFailed }
    failed.start(request)
    try await waitUntil { !failed.running }
    #expect(failed.error != nil && !failed.running)
  }

  @Test func stoppingOrFailingAnotherSearchRetainsTheVerifiedPreview() async throws {
    let (stream, continuation) = AsyncThrowingStream<FontFitResult, Error>.makeStream()
    let calls = Mutex(0)
    let fit = FontFitModel { request, candidate in
      calls.withLock { $0 += 1 }
      if request.options.size { return stream }
      if !request.options.features.isEmpty { throw SimilarityError.renderingFailed }
      return try await Self.fitResult(request, candidate)
    }
    let model = WorkbenchModel()
    let initial = model.comparison
    let b = try #require(initial.b)
    var options = FontFitOptions(config: b)
    options.axes = []
    options.features = []
    func request() -> FontFitModel.Request {
      .init(a: initial.a, b: b, text: initial.text, options: options, scale: 2)
    }
    fit.start(request())
    try await waitUntil { !fit.running }
    let preview = try #require(fit.result)
    options.tracking = false
    options.size = true
    fit.start(request())
    try await waitUntil { calls.withLock { $0 } == 2 }
    #expect(fit.running && fit.result?.proposed == preview.proposed)
    fit.stop()
    continuation.yield(
      .init(
        proposed: b, originalScore: Self.score(1), score: Self.score(0), evaluations: 99,
        finished: true))
    continuation.finish()
    try await Task.sleep(for: .milliseconds(20))
    #expect(
      fit.result?.proposed == preview.proposed && fit.result?.evaluations == preview.evaluations)
    options.size = false
    options.features = ["ot.kern"]
    fit.start(request())
    try await waitUntil { !fit.running }
    #expect(fit.error != nil && fit.result?.proposed == preview.proposed)
    #expect(fit.apply(to: model, undoManager: nil))
    #expect(model.comparison.b == preview.proposed && model.comparison.a == initial.a)
  }
}

extension SimilarityModelTests {
  @Test(arguments: [false, true])
  func matchKeepsItsHeightAndPluralizesEvaluationCounts(fail: Bool) async throws {
    let model = WorkbenchModel()
    let b = try #require(model.comparison.b)
    let (stream, continuation) = AsyncThrowingStream<FontFitResult, Error>.makeStream()
    let fit = FontFitModel { _, _ in stream }
    let host = WorkbenchTestHost(WorkbenchView(model: model, fit: fit, matching: true))
    defer {
      host.window.close()
      continuation.finish()
    }
    try await host.settle()
    let height = host.view.fittingSize.height
    #expect(height > 0)
    try await host.press("Font B Optimize tracking")
    try await host.settle { fit.running }
    #expect(abs(host.view.fittingSize.height - height) < 0.5)
    for count in [1, 2] {
      continuation.yield(
        .init(
          proposed: b, originalScore: Self.score(0.5), score: Self.score(0.5),
          evaluations: count, finished: false))
      try await host.settle { fit.result?.evaluations == count }
      let suffix = count == 1 ? "1 evaluation" : "2 evaluations"
      let status = try await host.element("Matching distance")
      let text: String? = status.accessibilityValue?()
      #expect(text?.hasSuffix(suffix) == true)
      #expect(abs(host.view.fittingSize.height - height) < 0.5)
    }
    if fail {
      continuation.finish(
        throwing: SimilarityError.unsupportedText(
          String(repeating: "Long font name ", count: 40), "a"))
    } else {
      continuation.finish()
    }
    try await host.settle { !fit.running }
    #expect((fit.error != nil) == fail)
    #expect(abs(host.view.fittingSize.height - height) < 0.5)
  }

  @Test func changingMatchingInputsClearsThePreviewWithoutStartingAnotherSearch() async throws {
    let model = WorkbenchModel()
    let fit = FontFitModel(load: Self.fitResult)
    let host = WorkbenchTestHost(WorkbenchView(model: model, fit: fit, matching: true))
    defer { host.window.close() }
    try await host.press("Font B Optimize tracking")
    try await host.settle { !fit.running && fit.result != nil }
    model.comparison.b?.size += 1
    try await host.settle { fit.result == nil }
    #expect(!fit.running && !host.isEnabled("Apply"))
    try await host.press("Match…")
    try await host.press("Font B Optimize size")
    try await host.settle { !fit.running && fit.result != nil }
    #expect(fit.result?.proposed.tracking == model.comparison.b?.tracking)
    #expect(fit.result?.evaluations == 10)
    model.comparison.b = nil
    try await host.settle { fit.result == nil }
    #expect(!fit.running && !host.isEnabled("Apply"))
  }

  @Test func similarityReorderingPreservesKeyboardSelectionAndSearchDoesNotReload() async throws {
    let (stream, continuation) = AsyncThrowingStream<FamilySimilarity, Error>.makeStream()
    let calls = Mutex(0)
    let ranking = FamilySimilarityModel { _, _, _ in
      calls.withLock { $0 += 1 }
      return stream
    }
    ranking.sort = .similarity
    var chosen: String?
    let host = WorkbenchTestHost(
      FontFamilyPicker(
        families: ["Alpha", "Beta", "Missing"], currentFamily: "Beta", allowsNone: true,
        ranking: ranking, reference: .init("ArialMT"), choose: { chosen = $0 }), width: 300,
      height: 400)
    defer { host.window.close() }
    try await host.settle { calls.withLock { $0 } == 1 }
    continuation.yield(.init(family: "Beta", score: Self.score(0.1)))
    continuation.yield(.init(family: "Alpha", score: Self.score(0.2)))
    continuation.yield(.init(family: "Missing", score: nil, unavailableReason: "Missing character"))
    continuation.finish()
    try await host.settle { !ranking.comparing && ranking.results.count == 3 }
    let search = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen == "Beta")
    host.enter("Al", in: search)
    try await host.settle()
    #expect(calls.withLock { $0 } == 1)
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen == "Alpha")
    try await host.press("Name")
    try await host.settle { ranking.sort == .name }
    #expect(ranking.sort == .name)
  }

  @Test func matchOptimizesOneSettingAtATimeAndAccumulatesThePreview() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    let fit = FontFitModel(load: Self.fitResult)
    let host = WorkbenchTestHost(
      WorkbenchView(model: model, fit: fit, matching: true), width: 1440, height: 900)
    defer { host.window.close() }
    try await host.settle()
    #expect(fit.result == nil && !fit.running)
    #expect(!host.isEnabled("Apply"))
    let initial = try #require(model.comparison.b)
    let axis = try #require(model.comparison.b?.face.axes.first)
    try await host.choose("Font B Optimize axes", nativeTitles: [axis.name], item: axis.name)
    try await host.settle { !fit.running && fit.result != nil && host.isEnabled("Apply") }
    var expected = initial
    expected.axes[axis.id] = (expected.axes[axis.id] ?? 0) + 0.1
    #expect(fit.result?.proposed == expected)
    let feature = try #require(initial.face.features.first { $0.id == "ot.kern" })
    try await host.choose(
      "Font B Optimize typography", nativeTitles: [feature.name], item: feature.name)
    try await host.settle { fit.result?.evaluations == 20 && host.isEnabled("Apply") }
    expected.features["ot.kern"] = 0
    #expect(fit.result?.proposed == expected)
    try await host.press("Font B Optimize tracking")
    try await host.settle { fit.result?.evaluations == 30 && host.isEnabled("Apply") }
    expected.tracking = 0.025
    #expect(fit.result?.proposed == expected)
    try await host.press("Font B Optimize size")
    try await host.settle { fit.result?.evaluations == 40 && host.isEnabled("Apply") }
    expected.size += 2
    #expect(fit.result?.proposed == expected)
    try await host.press("Font B Optimize leading")
    try await host.settle { fit.result?.evaluations == 50 && host.isEnabled("Apply") }
    expected.leading = 36
    #expect(fit.result?.proposed == expected)
    try await host.press("Font B Optimize tracking")
    try await host.settle { fit.result?.evaluations == 60 && host.isEnabled("Apply") }
    #expect(fit.result?.proposed == expected)
    #expect(!fit.searchImproved && fit.result?.improved == true)
    #expect(host.isEnabled("Apply"))
    #expect(model.comparison.a == model.comparison.b)
    try await host.press("Apply")
    #expect(model.comparison.b == expected)
    host.window.undoManager?.undo()
    #expect(model.comparison.b == initial)
  }

  @Test func matchShowsFailuresAndNoImprovementWithoutEnablingApply() async throws {
    let comparison = Comparison()
    let model = WorkbenchModel(comparison: comparison)
    for fail in [false, true] {
      let fit = FontFitModel { request, _ in
        if fail { throw SimilarityError.unsupportedText(request.b.postScriptName, "🦄") }
        return AsyncThrowingStream {
          $0.yield(
            .init(
              proposed: request.b, originalScore: Self.score(0.1), score: Self.score(0.1),
              evaluations: 10, finished: true))
          $0.finish()
        }
      }
      let host = WorkbenchTestHost(WorkbenchView(model: model, fit: fit, matching: true))
      defer { host.window.close() }
      try await host.press("Font B Optimize tracking")
      try await host.settle { fail ? fit.error != nil : (fit.result != nil && !fit.running) }
      #expect(try await host.element("Apply").isAccessibilityEnabled?() == false)
      #expect(model.comparison == comparison)
      if fail { #expect(fit.error != nil) }
    }
    let (stream, continuation) = AsyncThrowingStream<FontFitResult, Error>.makeStream()
    let fit = FontFitModel { _, _ in stream }
    let host = WorkbenchTestHost(WorkbenchView(model: model, fit: fit, matching: true))
    defer {
      host.window.close()
      continuation.finish()
    }
    try await host.press("Font B Optimize tracking")
    try await host.settle { fit.running }
    #expect(fit.running)
    #expect(!host.isEnabled("Font B Optimize size"))
    try await host.press("Stop")
    #expect(!fit.running && model.comparison == comparison)
  }
}

extension SimilarityModelTests {
  @Test func unavailableReferenceIsVisibleAndSortPreferencesBelongToTheWindow() async throws {
    let first = WorkbenchModel()
    let second = WorkbenchModel()
    first.familySimilarity.sort = .similarity
    #expect(second.familySimilarity.sort == .name)
    let host = WorkbenchTestHost(
      FontFamilyPicker(
        families: ["Arial"], currentFamily: "Arial", allowsNone: true,
        ranking: first.familySimilarity, reference: .init("TypefaceOff-Missing"), choose: { _ in }),
      width: 300, height: 400)
    defer { host.window.close() }
    try await host.settle {
      first.familySimilarity.error?.contains("Font unavailable") == true
        && !first.familySimilarity.comparing
    }
    #expect(first.familySimilarity.error?.contains("Font unavailable") == true)
    #expect(!first.familySimilarity.comparing)
  }

  @Test func removingTheMatchViewCancelsItsWork() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    var b = FontConfiguration(name)
    b.axes = [:]
    b.features["ot.kern"] = 999
    let model = WorkbenchModel(comparison: Comparison(a: b, b: b))
    let (stream, continuation) = AsyncThrowingStream<FontFitResult, Error>.makeStream()
    let fit = FontFitModel { _, _ in stream }
    let host = WorkbenchTestHost(AnyView(WorkbenchView(model: model, fit: fit, matching: true)))
    defer {
      host.window.close()
      continuation.finish()
    }
    _ = try await host.element("Font B Optimize typography")
    try await host.press("Font B Optimize tracking")
    try await host.settle { fit.running }
    #expect(fit.running)
    host.setContent(AnyView(EmptyView()))
    try await host.settle { !fit.running }
    #expect(!fit.running)
  }

  @Test func anOldFamilyRequestCannotReplaceANewerRequest() async throws {
    let (first, old) = AsyncThrowingStream<FamilySimilarity, Error>.makeStream()
    let (second, current) = AsyncThrowingStream<FamilySimilarity, Error>.makeStream()
    let model = FamilySimilarityModel { reference, _, _ in reference.size == 22 ? first : second }
    model.sort = .similarity
    let a = FontConfiguration("ArialMT")
    var b = a
    b.size = 23
    let catalog = FontCatalog()
    let stale = Task { await model.update(.init(reference: a, scale: 2), catalog: catalog) }
    await Task.yield()
    let fresh = Task { await model.update(.init(reference: b, scale: 2), catalog: catalog) }
    await Task.yield()
    current.yield(.init(family: "Current", score: Self.score(0)))
    current.finish()
    await fresh.value
    old.yield(.init(family: "Stale", score: Self.score(0)))
    old.finish()
    await stale.value
    #expect(model.results["Current"] != nil && model.results["Stale"] == nil)
  }
}
