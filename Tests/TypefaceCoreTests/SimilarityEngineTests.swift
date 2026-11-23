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

import Foundation
import Synchronization
import Testing

@testable import TypefaceCore

extension SimilarityTests {
  @Test func leastRecentlyUsedEvictsOldestFirstAndReturnsDisplacedValues() {
    var cache = LeastRecentlyUsed<String, Int>(capacity: 10)
    #expect(cache.insert(1, bytes: 4, for: "a").isEmpty)
    #expect(cache.insert(2, bytes: 4, for: "b").isEmpty)
    #expect(cache.value(for: "a") == 1)
    #expect(cache.insert(3, bytes: 4, for: "c") == [2])
    #expect(cache.value(for: "b") == nil)
    #expect(cache.insert(4, bytes: 4, for: "a") == [1])
    #expect(cache.bytes == 8)
    #expect(cache.insert(5, bytes: 11, for: "c") == [3])
    #expect(cache.value(for: "c") == nil && cache.bytes == 4)
    #expect(cache.insert(6, bytes: 6, for: "d").isEmpty)
    #expect(cache.insert(7, bytes: 10, for: "e") == [4, 6])
    #expect(cache.value(for: "e") == 7 && cache.bytes == 10)
    #expect(LeastRecentlyUsed<String, Int>(capacity: -1).capacity == 0)
  }

  @Test func boundedMapPreservesOrderAndStartsNothingAfterStop() async throws {
    for concurrency in [1, 3] {
      let doubled = try await FontSimilarityEngine.map(10, concurrency: concurrency) { $0 * 2 }
      #expect(doubled.compactMap { $0 } == (0..<10).map { $0 * 2 })
      let started = Mutex<Set<Int>>([])
      let stopped = try await FontSimilarityEngine.map(
        10, concurrency: concurrency, stop: { $0 == 4 },
        transform: { index in
          started.withLock { _ = $0.insert(index) }
          return index
        })
      #expect(stopped.prefix(5).compactMap { $0 } == [0, 1, 2, 3, 4])
      if concurrency == 1 { #expect(started.withLock { $0 } == Set(0...4)) }
    }
    await #expect(throws: CancellationError.self) {
      _ = try await FontSimilarityEngine.map(4, concurrency: 2) { _ -> Int in
        throw CancellationError()
      }
    }
  }

  @Test func identicalConfigurationsRenderOnceAndTextConcurrencyIsExact() async throws {
    let a = FontConfiguration("HelveticaNeue")
    let b = FontConfiguration("ArialMT")
    let engine = FontSimilarityEngine()
    #expect(try await engine.compare(a: a, b: a, corpus: corpus).total == 0)
    #expect(await engine.renderCount == corpus.glyphs.count + corpus.runs.count)
    let serial = try await FontSimilarityEngine().compare(
      a: a, b: b, corpus: .diagnostic, scale: 2, concurrency: 1)
    let parallel = try await FontSimilarityEngine().compare(
      a: a, b: b, corpus: .diagnostic, scale: 2, concurrency: 8)
    #expect(serial == parallel)
  }

  @Test func failuresAreCachedAndOnlyEqualSizeScoresAreReusedInReverse() async throws {
    let a = FontConfiguration("HelveticaNeue")
    let b = FontConfiguration("ArialMT")
    // Scores fit in this budget, but none of these images do.
    let engine = FontSimilarityEngine(cacheBytes: 16_000)
    let corpus = SimilarityCorpus(glyphs: ["W"], runs: ["AV To"])
    let ab = try await engine.compare(a: a, b: b, corpus: corpus)
    var renders = await engine.renderCount
    #expect(try await engine.compare(a: b, b: a, corpus: corpus) == ab)
    #expect(await engine.renderCount == renders)
    var larger = b
    larger.size = 30
    _ = try await engine.compare(a: a, b: larger, corpus: corpus)
    renders = await engine.renderCount
    _ = try await engine.compare(a: larger, b: a, corpus: corpus)
    #expect(await engine.renderCount > renders)

    let missing = "\u{10FFFF}"
    let partial = SimilarityCorpus(glyphs: ["W", missing], runs: [])
    await #expect(throws: SimilarityError.unsupportedText(a.postScriptName, missing)) {
      try await engine.compare(a: a, b: b, corpus: partial)
    }
    renders = await engine.renderCount
    await #expect(throws: SimilarityError.unsupportedText(a.postScriptName, missing)) {
      try await engine.compare(a: a, b: b, corpus: partial)
    }
    #expect(await engine.renderCount == renders)
    await #expect(throws: SimilarityError.unsupportedText(b.postScriptName, missing)) {
      try await engine.compare(a: b, b: a, corpus: partial)
    }

    let huge = SimilarityCorpus(glyphs: ["W"], runs: [String(repeating: "M", count: 20000)])
    for _ in 0..<2 {
      renders = await engine.renderCount
      await #expect(throws: SimilarityError.renderingFailed) {
        try await engine.compare(a: a, b: b, corpus: huge, scale: 4)
      }
      #expect(await engine.renderCount > renders)
    }
  }

  @Test func onlyTheMetricTermDependsOnWhichSideIsTheReference() async throws {
    let engine = FontSimilarityEngine()
    let a = FontConfiguration("HelveticaNeue")
    var b = FontConfiguration("ArialMT")
    b.size = 30
    let forward = try await engine.compare(a: a, b: b, corpus: corpus)
    let reverse = try await engine.compare(a: b, b: a, corpus: corpus)
    #expect(forward.geometry == reverse.geometry && forward.appearance == reverse.appearance)
    #expect(forward.shapedText == reverse.shapedText)
    #expect(forward.metrics > reverse.metrics)
  }

  @Test func differenceMatchesTheScalarDefinition() throws {
    var seed: UInt64 = 0x5eed
    func random(_ range: ClosedRange<Int>) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return range.lowerBound + Int(seed >> 33) % range.count
    }
    func image() -> SimilarityImage {
      let width = random(1...19)
      let height = random(1...17)
      let pixels = (0..<width * height).map { _ in
        [0, 0, 1, Float(random(0...255)) / 255][random(0...3)]
      }
      return SimilarityImage(
        x: random(-9...9), y: random(-9...9), width: width, height: height, pixels: pixels,
        radius: Float(random(2...12)) / 2)
    }
    var pairs = (0..<200).map { _ in (image(), image()) }
    let helvetica = FontConfiguration("HelveticaNeue")
    let times = FontConfiguration("TimesNewRomanPSMT")
    for text in ["g", "W", "AV To"] {
      pairs.append(
        (
          try SimilarityImage.render(
            text, config: helvetica, scale: 2, tracking: true, radius: 5.5),
          try SimilarityImage.render(text, config: times, scale: 2, tracking: true, radius: 3)
        ))
    }
    for (left, right) in pairs {
      let fast = try left.difference(from: right)
      let reverse = try right.difference(from: left)
      let expected = Self.scalarDifference(left, right)
      #expect(fast.geometry == expected.geometry && fast.appearance == expected.appearance)
      #expect(fast.geometry == reverse.geometry && fast.appearance == reverse.appearance)
    }
  }

  @Test func distanceTransformMatchesBruteForceForNarrowImages() {
    for (width, height) in [(1, 1), (1, 7), (7, 1), (13, 11)] {
      let sites = (0..<width * height).map { $0 % 5 == 2 }
      let distances = SimilarityImage.distanceTransform(sites, width: width, height: height)
      for index in sites.indices {
        let nearest = sites.indices.filter { sites[$0] }.map {
          Float(
            (index % width - $0 % width) * (index % width - $0 % width)
              + (index / width - $0 / width) * (index / width - $0 / width))
        }.min()
        #expect(distances[index] == nearest ?? 1e12)
      }
    }
  }

  static func scalarDifference(_ left: SimilarityImage, _ right: SimilarityImage) -> (
    geometry: Double, appearance: Double
  ) {
    if left.x == right.x, left.y == right.y, left.width == right.width,
      left.height == right.height, left.radius == right.radius, left.pixels == right.pixels
    {
      return (0, 0)
    }
    var geometry = 0.0
    var band = 0.0
    var differences = [Double](repeating: 0, count: 3)
    var unions = differences
    let leftChannels = [left.pixels] + left.blurred
    let rightChannels = [right.pixels] + right.blurred
    let radius = max(left.radius, right.radius)
    for row in min(left.y, right.y)..<max(left.y + left.height, right.y + right.height) {
      for column in min(left.x, right.x)..<max(left.x + left.width, right.x + right.width) {
        let a = left.value(left.field, x: column, y: row, outside: radius)
        let b = right.value(right.field, x: column, y: row, outside: radius)
        if abs(a) < radius || abs(b) < radius {
          geometry += Double(abs(a - b) / (2 * radius))
          band += 1
        }
        for channel in 0..<3 {
          let l = left.value(leftChannels[channel], x: column, y: row)
          let r = right.value(rightChannels[channel], x: column, y: row)
          differences[channel] += Double(abs(l - r))
          unions[channel] += Double(max(l, r))
        }
      }
    }
    let appearance = zip(differences, unions).map { $1 == 0 ? 0 : $0 / $1 }.reduce(0, +) / 3
    return (band == 0 ? 0 : geometry / band, appearance)
  }
}

extension SimilarityImage {
  static func render(
    _ text: String, config: FontConfiguration, scale: Double, tracking: Bool, radius: Float
  ) throws -> Self {
    Self(try rasterize(text, config: config, scale: scale, tracking: tracking, radius: radius))
  }

  static func rasterize(
    _ text: String, config: FontConfiguration, scale: Double, tracking: Bool, radius: Float
  ) throws -> Raster {
    guard FontRenderer.supports(text, config: config, size: config.size, tracking: tracking) else {
      throw SimilarityError.unsupportedText(config.postScriptName, text)
    }
    return try rasterize(
      FontRenderer.line(text, config: config, size: config.size, tracking: tracking),
      scale: scale, radius: radius)
  }
}
