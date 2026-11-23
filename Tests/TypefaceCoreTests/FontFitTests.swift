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

import CoreText
import Foundation
import Synchronization
import Testing

@testable import TypefaceCore

@Suite(.serialized) struct FontFitTests {
  let catalog = FontCatalog()
  let corpus = SimilarityCorpus(
    glyphs: ["a", "g", "I"], runs: ["AV", "fi"], requiredText: "AV fi")

  static func score(_ value: Double) -> SimilarityScore {
    .init(geometry: value, appearance: value, shapedText: value, metrics: value)
  }

  // A deadline that can expire first makes the result depend on machine speed.
  static func evaluations(_ count: Int) -> FontFitBudget {
    .init(seconds: 60, evaluations: count)
  }

  @Test(arguments: [Double?.none, 1, 36, 288])
  func leadingMatchesReferenceSpacingAndPreservesOtherSettings(leading: Double?) async throws {
    var a = FontConfiguration("ArialMT")
    a.leading = leading
    var b = a
    b.leading = leading == nil ? 48 : nil
    var options = FontFitOptions(config: b)
    options.axes = []
    options.features = []
    options.tracking = false
    options.leading = true
    #expect(!options.isEmpty)
    let domain = FontFitDomain(original: b, options: options)
    #expect(domain.constrained(a).leading == a.leading)
    var final: FontFitResult?
    for try await result in await FontFitEngine().fit(
      a: a, b: b, options: options, corpus: corpus, catalog: catalog, scale: 1,
      budget: Self.evaluations(100))
    { final = result }
    let result = try #require(final)
    var expected = b
    expected.leading = FontRenderer.leading(a)
    #expect(result.finished && result.improved && result.evaluations == 2)
    #expect(result.proposed == expected)
    #expect(result.score.total < 1e-6)
    options.size = true
    #expect(FontFitDomain(original: b, options: options).discreteCandidates(reference: a) == nil)
  }

  @Test(arguments: [0.0, -1, .infinity, .nan])
  func invalidLeadingFailsBeforePublishingScores(leading: Double) async throws {
    var a = FontConfiguration("ArialMT")
    a.leading = leading
    let engine = FontFitEngine()
    await #expect(throws: SimilarityError.invalidConfiguration) {
      for try await _ in await engine.fit(
        a: a, b: a, options: .init(config: a), corpus: corpus, catalog: catalog)
      { Issue.record("Invalid leading produced a result") }
    }
  }

  @Test(arguments: [Int?.none, 0, 1])
  func booleanSearchEvaluatesEachChoiceOnceUsingTheFullCorpus(initial: Int?) async throws {
    var b = FontConfiguration("ArialMT")
    b.features["ot.kern"] = initial
    b.leading = 31
    var options = FontFitOptions(config: b)
    options.axes = []
    options.features = ["ot.kern"]
    options.tracking = false
    let calls = Mutex<[FontConfiguration]>([])
    let engine = FontFitEngine { _, candidate, samples, _ in
      #expect(samples == corpus)
      calls.withLock { $0.append(candidate) }
      return Self.score(candidate.features["ot.kern"] == 1 ? 0 : 0.2)
    }
    var final: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(1000))
    { final = result }
    let evaluated = calls.withLock { $0 }
    #expect(evaluated.count == (initial == nil ? 3 : 2))
    #expect(Set(evaluated.compactMap { $0.features["ot.kern"] }) == [0, 1])
    #expect(Set(evaluated).count == evaluated.count)
    #expect(
      evaluated.allSatisfy { candidate in
        var restored = candidate
        restored.features["ot.kern"] = initial
        return restored == b
      })
    #expect(final?.finished == true && final?.proposed.features["ot.kern"] == 1)
  }

  @Test func discreteSearchResumesAfterItsBudgetAndRejectsInvalidChoices() async throws {
    let b = FontConfiguration("ArialMT")
    var options = FontFitOptions(config: b)
    options.axes = []
    options.features = ["ot.kern"]
    options.tracking = false
    let engine = FontFitEngine { _, candidate, _, _ in
      if candidate.features["ot.kern"] == 0 { throw SimilarityError.unsupportedText("Arial", "a") }
      return Self.score(candidate.features["ot.kern"] == 1 ? 0.1 : 0.2)
    }
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(1))
    { #expect(result.evaluations == 1 && result.proposed == b) }
    var final: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(10), refine: true)
    { final = result }
    #expect(final?.finished == true && final?.improved == true)
    #expect(final?.evaluations == 3)
  }

  @Test func constrainedSearchKeepsFaceSizeLocksAndAutomaticShaping() throws {
    var b = FontConfiguration(try #require(FontCatalog().preferredFace(in: "Skia")).id)
    b.tracking = 0.08
    b.features["ot.tnum"] = 1
    var options = FontFitOptions(config: b)
    #expect(!options.size && options.tracking && !options.axes.isEmpty)
    options.features = []
    options.axes = []
    let domain = FontFitDomain(original: b, options: options)
    let neighbors = domain.neighbors(b, step: 0.25, priority: [])
    #expect(neighbors.contains { $0.tracking == 0 })
    #expect(
      neighbors.allSatisfy {
        $0.postScriptName == b.postScriptName && $0.size == b.size && $0.axes == b.axes
          && $0.features == b.features
      })
    let other = FontConfiguration("ArialMT")
    let bounded = domain.constrained(other)
    #expect(
      bounded.tracking == 0 && bounded.size == b.size && bounded.postScriptName == b.postScriptName)
    let number = FontFeature(
      id: "ot.pnum", name: "Proportional",
      options: [.init(name: "Off", value: 0), .init(name: "On", value: 1)], defaultValue: 0)
    #expect(domain.setting(b, feature: number, value: 1) == nil)
    options.features = [number.id]
    let partner = FontFeature(
      id: "ot.tnum", name: "Tabular", options: number.options, defaultValue: 0)
    let lockedPartner = FontFitDomain(
      original: b, options: options, availableFeatures: [number, partner])
    #expect(lockedPartner.setting(b, feature: number, value: 1) == nil)
    b.features = [:]
    let absentPartner = FontFitDomain(original: b, options: options, availableFeatures: [number])
    #expect(absentPartner.setting(b, feature: number, value: 1)?.features["ot.tnum"] == nil)
    var requiredPartner = partner
    requiredPartner.required = true
    let protected = FontFitDomain(
      original: b, options: options, availableFeatures: [number, requiredPartner])
    #expect(protected.setting(b, feature: number, value: 1)?.features["ot.tnum"] == nil)
    let unlockedPartner = FontFitDomain(
      original: b, options: options, availableFeatures: [number, partner])
    #expect(unlockedPartner.setting(b, feature: number, value: 1)?.features["ot.tnum"] == nil)
    options.features = ["ot.tnum", "ot.pnum"]
    let enabled = FontFitDomain(
      original: b, options: options, availableFeatures: [number, partner])
    #expect(enabled.setting(b, feature: number, value: 1)?.features["ot.tnum"] == 0)
    options.tracking = false
    options.features = []
    #expect(options.isEmpty)
    let noSettings = FontFitDomain(original: b, options: options)
    #expect(noSettings.neighbors(b, step: 0.25, priority: []).isEmpty)
  }

  @Test func multivaluedCategoricalStatesAndPairedChangesAreSearched() throws {
    let b = FontConfiguration("ArialMT")
    let feature = FontFeature(
      id: "ot.cv01", name: "Alternate", options: (0...2).map { .init(name: String($0), value: $0) },
      defaultValue: 0)
    let other = FontFeature(
      id: "ot.ss01", name: "Set",
      options: [.init(name: "Off", value: 0), .init(name: "On", value: 1)], defaultValue: 0)
    let required = FontFeature(
      id: "ot.private", name: "Required", options: feature.options, defaultValue: 1, required: true)
    var options = FontFitOptions(config: b)
    options.features = [feature.id, other.id, required.id]
    options.tracking = false
    let domain = FontFitDomain(
      original: b, options: options, availableFeatures: [feature, other, required])
    #expect(domain.features.count == 2)
    var sampled = other
    sampled.sample = "AV"
    var absentSample = feature
    absentSample.sample = "xy"
    let prioritized = FontFitDomain(
      original: b, options: options, availableFeatures: [absentSample, sampled, required])
    #expect(prioritized.priority(text: "AV") == [other.id, feature.id])
    #expect(prioritized.priority(text: "xy") == [feature.id, other.id])
    #expect(prioritized.priority(text: "AV xy") == [feature.id, other.id])
    let states = domain.categoricalSeeds()
    #expect(states.count == 12)
    #expect(domain.categoricalSeeds(limit: 2).isEmpty)
    let neighbors = domain.neighbors(b, step: 0.25, priority: [other.id])
    #expect(neighbors.contains { $0.features[feature.id] == 2 && $0.features[other.id] == 1 })
    #expect(neighbors.allSatisfy { $0.features[required.id] == nil })
    let huge = FontFeature(
      id: "ot.cv02", name: "Many", options: (0...4100).map { .init(name: String($0), value: $0) },
      defaultValue: 0)
    options.features = [huge.id, other.id]
    let large = FontFitDomain(original: b, options: options, availableFeatures: [huge, other])
    #expect(large.neighbors(b, step: 0.25, priority: []).count <= 4097)
  }

  @Test func boundedPatternSearchFindsACoupledMinimumAndRefineResumes() async throws {
    let b = FontConfiguration(try #require(FontCatalog().preferredFace(in: "Skia")).id)
    let axes = b.face.axes
    let weight = try #require(axes.first { $0.tag == "wght" })
    let width = try #require(axes.first { $0.tag == "wdth" })
    var options = FontFitOptions(config: b)
    options.features = []
    options.tracking = false
    let loss: @Sendable (FontConfiguration) -> Double = { config in
      let x = ((config.axes[weight.id] ?? 0) - weight.minimum) / (weight.maximum - weight.minimum)
      let y = ((config.axes[width.id] ?? 0) - width.minimum) / (width.maximum - width.minimum)
      // A narrow diagonal valley defeats a single pass of independent axis adjustments.
      return (pow(x - y - 0.05, 2) * 10 + pow(x - 0.65, 2) + pow(y - 0.6, 2)) / 20
    }
    let calls = Mutex(0)
    let engine = FontFitEngine { _, config, _, _ in
      calls.withLock { $0 += 1 }
      return Self.score(loss(config))
    }
    var quick: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(30))
    {
      #expect(result.score.total <= result.originalScore.total)
      quick = result
    }
    let first = try #require(quick)
    #expect(first.evaluations <= 30 && first.finished)
    var refined: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(1000), refine: true)
    {
      refined = result
    }
    let final = try #require(refined)
    #expect(final.evaluations > first.evaluations && final.evaluations <= first.evaluations + 1000)
    #expect(final.evaluations == calls.withLock { $0 })
    #expect(final.score.total <= first.score.total)
    #expect(final.score.total < 0.0001)
    #expect(final.proposed.size == b.size && final.proposed.tracking == b.tracking)
  }

  @Test func screeningCannotPublishAFullCorpusRegression() async throws {
    var b = FontConfiguration("ArialMT")
    b.tracking = 0.1
    var options = FontFitOptions(config: b)
    options.features = []
    let engine = FontFitEngine { _, config, input, _ in
      Self.score(
        input.requiredText.isEmpty ? abs(config.tracking) : abs(config.tracking - 0.1) + 0.1)
    }
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(100))
    {
      #expect(!result.improved && result.proposed == b)
      #expect(result.evaluations <= 100)
    }
  }

  @Test func nativeFitRetainsBaselineAndMatchesKnownVariableSettings() async throws {
    var a = FontConfiguration(try #require(FontCatalog().preferredFace(in: "Skia")).id)
    let b = a
    a.axes[tagNumber("wght")] = 1.2
    var options = FontFitOptions(config: b)
    options.features = []
    options.tracking = false
    let engine = FontFitEngine()
    var last: FontFitResult?
    for try await result in await engine.fit(
      a: a, b: b, options: options, corpus: corpus, catalog: catalog, scale: 1,
      budget: Self.evaluations(30))
    {
      #expect(result.score.total <= result.originalScore.total)
      last = result
    }
    let result = try #require(last)
    #expect(result.improved)
    #expect(result.proposed.axes[tagNumber("wght")] == a.axes[tagNumber("wght")])
    #expect(result.proposed.postScriptName == b.postScriptName)
    #expect(result.proposed.size == b.size && result.proposed.features == b.features)
  }

  @Test func budgetsErrorsAndCancellationDoNotLoseTheOriginal() async throws {
    let b = FontConfiguration("ArialMT")
    let options = FontFitOptions(config: b)
    let engine = FontFitEngine { _, _, _, _ in Self.score(0.2) }
    for budget in [FontFitBudget(seconds: 0, evaluations: 200), .init(seconds: 10, evaluations: 1)]
    {
      for try await result in await engine.fit(
        a: b, b: b, options: options, corpus: corpus, catalog: catalog, budget: budget)
      {
        #expect(result.evaluations == 1 && result.proposed == b)
      }
    }
    let fails = FontFitEngine { _, _, _, _ in throw SimilarityError.renderingFailed }
    await #expect(throws: SimilarityError.renderingFailed) {
      for try await _ in await fails.fit(
        a: b, b: b, options: options, corpus: corpus, catalog: catalog)
      {}
    }
    let slow = FontFitEngine { _, _, _, _ in
      try await Task.sleep(for: .seconds(5))
      return Self.score(1)
    }
    let task = Task {
      for try await _ in await slow.fit(
        a: b, b: b, options: options, corpus: corpus, catalog: catalog)
      {}
      try Task.checkCancellation()
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(FontFitBudget.quick.evaluations == 256 && FontFitBudget.refine.evaluations == 2048)
  }
}

extension FontFitTests {
  @Test func nonfiniteScreeningScoresCannotReplaceTheVerifiedBaseline() async throws {
    let b = FontConfiguration("ArialMT")
    var options = FontFitOptions(config: b)
    options.axes = []
    options.features = []
    let engine = FontFitEngine { _, candidate, _, _ in
      Self.score(candidate == b ? 0.5 : .infinity)
    }
    var last: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(50))
    {
      #expect(result.proposed == b && result.score.total.isFinite)
      last = result
    }
    #expect(last?.finished == true && (last?.evaluations ?? 0) > 1)
  }

  @Test func interactingFeaturesAreNotDiscardedWhenSingleChangesAreWorse() async throws {
    let b = FontConfiguration("ArialMT")
    let features = Array(b.face.features.filter { !$0.isAutomatic }.prefix(2))
    try #require(features.count == 2)
    var options = FontFitOptions(config: b)
    options.features = Set(features.map(\.id))
    options.axes = []
    options.tracking = true
    let engine = FontFitEngine { _, config, _, _ in
      let changed = features.filter {
        (config.features[$0.id] ?? $0.defaultValue) != $0.defaultValue
      }.count
      return Self.score(
        (changed == 2 ? 0.05 : changed == 1 ? 0.4 : 0.2) + abs(config.tracking - 0.035))
    }
    var final: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(400))
    {
      final = result
    }
    let result = try #require(final)
    #expect(result.score.total < 0.051)
    #expect(result.improved && result.proposed.size == b.size)
  }

  @Test func fullReadingSampleHasCoverageBeforeAnyCandidateIsEvaluated() async throws {
    let a = FontConfiguration("HelveticaNeue")
    let b = FontConfiguration("ArialMT")
    let corpus = SimilarityCorpus.fitting(reference: a, candidate: b, text: Sample.reading.text)
    let engine = FontFitEngine()
    for try await result in await engine.fit(
      a: a, b: b, options: .init(config: b), corpus: corpus, catalog: catalog, scale: 1,
      budget: .init(seconds: 0, evaluations: 1))
    {
      #expect(result.proposed == b && result.evaluations == 1)
    }
  }
}

extension FontFitTests {
  @Test func invalidCandidatesAreSkippedAndValidationResumesAtTheBudgetBoundary() async throws {
    var b = FontConfiguration("ArialMT")
    b.tracking = 0.1
    var options = FontFitOptions(config: b)
    options.axes = []
    options.features = []
    let attempts = Mutex<[FontConfiguration: Int]>([:])
    let engine = FontFitEngine { _, config, input, _ in
      attempts.withLock { $0[config, default: 0] += 1 }
      if config.tracking < 0 { throw SimilarityError.unsupportedText(config.postScriptName, "a") }
      if config.tracking > 0 && config.tracking < 0.08 && !input.requiredText.isEmpty {
        throw SimilarityError.renderingFailed
      }
      return Self.score(0.1 + abs(config.tracking))
    }
    var first: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(3))
    { first = result }
    #expect(first?.evaluations == 3)
    var final: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(100), refine: true)
    { final = result }
    #expect(final?.improved == true && final?.proposed.tracking == 0)
    let empty = SimilarityCorpus(glyphs: ["a"], runs: ["a"])
    let constant = FontFitEngine { _, _, _, _ in Self.score(0.5) }
    options.tracking = false
    options.size = true
    for try await result in await constant.fit(
      a: b, b: b, options: options, corpus: empty, catalog: catalog,
      budget: Self.evaluations(50))
    { #expect(!result.improved) }
    let weight = FontFitDomain.Dimension(property: .weight, range: 0.5...2)
    let variable = FontConfiguration(try #require(catalog.preferredFace(in: "Skia")).id)
    #expect(weight.value(variable) == variable.weight)
    #expect(weight.setting(variable, value: 3).weight == 2)
    let absent = FontFitDomain.Dimension(property: .axis(tagNumber("NONE")), range: 0...1)
    #expect(absent.value(variable) == 0)
  }
}

extension FontFitTests {
  @Test func finiteCategoricalSearchExhaustsEachStateWithoutRepeatingObjectiveCalls() async throws {
    let b = FontConfiguration("ArialMT")
    let features = Array(b.face.features.filter { !$0.isAutomatic }.prefix(2))
    var options = FontFitOptions(config: b)
    options.axes = []
    options.tracking = false
    options.features = Set(features.map(\.id))
    let engine = FontFitEngine { _, _, _, _ in Self.score(0.2) }
    var final: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(1000))
    { final = result }
    #expect(final?.finished == true && final?.improved == false)
    #expect((final?.evaluations ?? 1000) < 100)
  }

  @Test func supersededFitRequestsFailBeforePublishingTheirBaseline() async throws {
    let (requests, started) = AsyncStream<Double>.makeStream()
    let loader = SuspendedFitScore(started: started)
    let engine = FontFitEngine { _, b, _, _ in await loader.evaluate(size: b.size) }
    let b = FontConfiguration("ArialMT")
    var changed = b
    changed.size = 23
    let options = FontFitOptions(config: b)
    var iterator = requests.makeAsyncIterator()
    let stale = Task {
      for try await _ in await engine.fit(
        a: b, b: b, options: options, corpus: corpus, catalog: catalog,
        budget: .init(seconds: 0, evaluations: 1))
      {}
    }
    #expect(await iterator.next() == 22)
    let current = Task {
      for try await _ in await engine.fit(
        a: b, b: changed, options: options, corpus: corpus, catalog: catalog,
        budget: .init(seconds: 0, evaluations: 1))
      {}
    }
    #expect(await iterator.next() == 23)
    await loader.finish(size: 23)
    try await current.value
    await loader.finish(size: 22)
    await #expect(throws: CancellationError.self) { try await stale.value }
  }
}

private actor SuspendedFitScore {
  let started: AsyncStream<Double>.Continuation
  var pending: [Double: CheckedContinuation<SimilarityScore, Never>] = [:]
  init(started: AsyncStream<Double>.Continuation) { self.started = started }
  func evaluate(size: Double) async -> SimilarityScore {
    await withCheckedContinuation { continuation in
      pending[size] = continuation
      started.yield(size)
    }
  }
  func finish(size: Double) {
    pending.removeValue(forKey: size)?.resume(returning: FontFitTests.score(0.1))
  }
}

extension FontFitTests {
  @Test func featuresAbsentFromScreeningStillReceiveFullCorpusValidation() async throws {
    let b = FontConfiguration(try #require(catalog.preferredFace(in: "Skia")).id)
    var options = FontFitOptions(config: b)
    options.axes = []
    options.tracking = false
    let domain = FontFitDomain(original: b, options: options)
    #expect(domain.categoricalSeeds().isEmpty)
    let prioritized = Array(domain.priority(text: corpus.requiredText).prefix(2))
    let target = prioritized.compactMap { id in domain.features.first { $0.id == id } }
    try #require(target.count == 2)
    let engine = FontFitEngine { _, config, input, _ in
      let paired = target.allSatisfy {
        (config.features[$0.id] ?? $0.defaultValue) != $0.defaultValue
      }
      return Self.score(!input.requiredText.isEmpty && paired ? 0.1 : 0.2)
    }
    var final: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(512))
    { final = result }
    #expect(final?.score.total == 0.1 && final?.improved == true)
  }
}

extension FontFitTests {
  @Test func explicitDefaultFeaturesRemainReachableWhenAllOtherFeaturesAreLocked() async throws {
    var b = FontConfiguration("HelveticaNeue")
    b.tracking = 0.08
    let feature = try #require(b.face.features.first { $0.id == "aat.1.2" || $0.id == "ot.liga" })
    var options = FontFitOptions(config: b)
    options.features = [feature.id]
    options.axes = []
    options.tracking = false
    let domain = FontFitDomain(original: b, options: options)
    #expect(domain.categoricalSeeds().contains { $0.features[feature.id] == feature.defaultValue })
    #expect(
      domain.neighbors(b, step: 0.25, priority: []).contains {
        $0.features[feature.id] == feature.defaultValue
      })
    var a = b
    a.features[feature.id] = feature.defaultValue
    let samples = SimilarityCorpus(glyphs: ["f", "i"], runs: ["fi fl"], requiredText: "fi fl")
    let engine = FontFitEngine()
    for try await result in await engine.fit(
      a: a, b: b, options: options, corpus: samples, catalog: catalog,
      scale: 1, budget: Self.evaluations(30))
    {
      #expect(result.score.total <= result.originalScore.total)
      if result.finished {
        #expect(result.score.total < 1e-6)
        #expect(result.proposed.tracking == b.tracking)
      }
    }
  }
}

extension FontFitTests {
  @Test func largeFeatureSpacesDoNotStarveContinuousRefinement() async throws {
    let b = FontConfiguration(try #require(catalog.preferredFace(in: "Skia")).id)
    let width = try #require(b.face.axes.first { $0.tag == "wdth" })
    var options = FontFitOptions(config: b)
    options.axes = [width.id]
    options.tracking = false
    #expect(FontFitDomain(original: b, options: options).categoricalSeeds().isEmpty)
    let engine = FontFitEngine { _, config, _, _ in
      let normalized =
        ((config.axes[width.id] ?? width.defaultValue) - width.minimum)
        / (width.maximum - width.minimum)
      return Self.score(0.1 + abs(normalized - 0.62))
    }
    var final: FontFitResult?
    for try await result in await engine.fit(
      a: b, b: b, options: options, corpus: corpus, catalog: catalog,
      budget: Self.evaluations(100))
    { final = result }
    #expect((final?.score.total ?? 1) < 0.103)
    #expect((final?.evaluations ?? 101) <= 100)
  }
}
