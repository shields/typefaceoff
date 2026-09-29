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

  nonisolated static func fitResult(_ request: FontFitModel.Request, _ refine: Bool) async throws
    -> AsyncThrowingStream<FontFitResult, Error>
  {
    var config = request.b
    if request.options.tracking { config.tracking = 0.025 }
    if request.options.size { config.size += 2 }
    for axis in request.options.axes { config.axes[axis] = (config.axes[axis] ?? 0) + 0.1 }
    for feature in request.options.features { config.features[feature] = 0 }
    let improved = config != request.b
    let result = FontFitResult(
      proposed: config, originalScore: score(0.5), score: score(improved ? 0.3 : 0.5),
      evaluations: refine ? 20 : 10, finished: true)
    return AsyncThrowingStream {
      $0.yield(result)
      $0.finish()
    }
  }

  static func wait(until condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation)
    async throws
  {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "Timed out after 10 seconds", sourceLocation: sourceLocation)
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
    try await Self.wait { model.comparing }
    try await Task.sleep(for: .milliseconds(230))
    continuation.yield(.init(family: "Arial", score: Self.score(0)))
    try await Self.wait { model.results.count == 1 }
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
    try await Self.wait { !fit.running }
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
    fit.start(request, refine: true)
    try await Self.wait { !fit.running }
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
    try await Self.wait { !failed.running }
    #expect(failed.error != nil && !failed.running)
  }
}

extension SimilarityModelTests {
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
    try await host.settle()
    continuation.yield(.init(family: "Beta", score: Self.score(0.1)))
    continuation.yield(.init(family: "Alpha", score: Self.score(0.2)))
    continuation.yield(.init(family: "Missing", score: nil, unavailableReason: "Missing character"))
    continuation.finish()
    try await host.settle()
    let search = try #require(host.subviews.compactMap { $0 as? NSSearchField }.first)
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen == "Beta")
    host.enter("Al", in: search)
    try await host.settle()
    #expect(calls.withLock { $0 } == 1)
    search.currentEditor()?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(chosen == "Alpha")
    try await host.press("Name")
    try await host.settle()
    #expect(ranking.sort == .name)
  }

  @Test func matchLocksAxesAndFeaturesAndSupportsStopAndRefine() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    let model = WorkbenchModel(comparison: Comparison(a: .init(name), b: .init(name)))
    let fit = FontFitModel(load: Self.fitResult)
    let host = WorkbenchTestHost(MatchSheet(model: model, fit: fit), width: 600, height: 750)
    defer { host.window.close() }
    try await host.settle()
    let axis = try #require(model.comparison.b?.face.axes.first)
    try await host.press(axis.name)
    try await host.settle()
    #expect(fit.result?.proposed.axes[axis.id] == model.comparison.b?.axes[axis.id])
    try await host.press(axis.name)
    try await host.press("Typography")
    try await host.settle()
    try await host.press("Kerning")
    try await host.settle()
    #expect(fit.result?.proposed.features["ot.kern"] == nil)
    try await host.press("Kerning")
    try await host.settle()
    try await host.press("Refine")
    try await host.settle()
    #expect(fit.result?.evaluations == 20)
    #expect(model.comparison.a == model.comparison.b)
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
      let host = WorkbenchTestHost(MatchSheet(model: model, fit: fit))
      try await host.settle()
      #expect(try await host.element("Apply").isAccessibilityEnabled?() == false)
      #expect(model.comparison == comparison)
      if fail { #expect(fit.error != nil) }
      host.window.close()
    }
    let (stream, continuation) = AsyncThrowingStream<FontFitResult, Error>.makeStream()
    let fit = FontFitModel { _, _ in stream }
    let host = WorkbenchTestHost(MatchSheet(model: model, fit: fit))
    defer {
      host.window.close()
      continuation.finish()
    }
    try await host.settle()
    #expect(fit.running)
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
    try await host.settle()
    #expect(first.familySimilarity.error?.contains("Font unavailable") == true)
    #expect(!first.familySimilarity.comparing)
  }

  @Test func removingTheMatchViewCancelsItsWorkAndDefaultsMissingAxes() async throws {
    let name = try #require(FontCatalog().preferredFace(in: "Skia")).id
    var b = FontConfiguration(name)
    b.axes = [:]
    let model = WorkbenchModel(comparison: Comparison(a: b, b: b))
    let (stream, continuation) = AsyncThrowingStream<FontFitResult, Error>.makeStream()
    let fit = FontFitModel { _, _ in stream }
    let host = WorkbenchTestHost(AnyView(MatchSheet(model: model, fit: fit)))
    defer {
      host.window.close()
      continuation.finish()
    }
    try await host.settle()
    #expect(fit.running)
    host.setContent(AnyView(EmptyView()))
    try await host.settle()
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
