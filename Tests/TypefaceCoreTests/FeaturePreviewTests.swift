import CoreText
import Foundation
import Synchronization
import Testing

@testable import TypefaceCore

@Suite struct FeaturePreviewTests {
  @Test @MainActor func searchesRunOffTheMainThreadAndShareCachedMisses() async throws {
    let calls = Mutex(0)
    let engine = FontFeaturePreviewEngine { _, _ in
      #expect(!Thread.isMainThread)
      calls.withLock { $0 += 1 }
      return nil
    }
    let config = FontConfiguration("HelveticaNeue")
    let featureCount = config.face.features.filter { !$0.isAutomatic }.count
    async let left = engine.previews(config: config)
    async let right = engine.previews(config: config)
    let results = try await (left, right)
    #expect(results.0.isEmpty && results.1.isEmpty)
    #expect(calls.withLock { $0 } == featureCount)
    var larger = config
    larger.size = 72
    #expect(try await engine.previews(config: larger).isEmpty)
    #expect(calls.withLock { $0 } == featureCount)
  }

  @Test func cacheIncludesAxesTrackingAndTypographyAndHasABoundedLifetime() async throws {
    let calls = Mutex(0)
    let engine = FontFeaturePreviewEngine { _, _ in
      calls.withLock { $0 += 1 }
      return nil
    }
    let original = FontConfiguration("HelveticaNeue")
    let count = original.face.features.filter { !$0.isAutomatic }.count
    _ = try await engine.previews(config: original)
    var config = original
    config.axes[tagNumber("wght")] = 600
    _ = try await engine.previews(config: config)
    config.tracking = 0.01
    _ = try await engine.previews(config: config)
    config.features["aat.1.2"] = 3
    _ = try await engine.previews(config: config)
    #expect(calls.withLock { $0 } == 4 * count)
    for value in 2...7 {
      config.tracking = Double(value) / 100
      _ = try await engine.previews(config: config)
    }
    let before = calls.withLock { $0 }
    _ = try await engine.previews(config: original)
    #expect(calls.withLock { $0 } == before + count)
  }

  @Test func cancellationStopsSearchesAndDoesNotCacheIncompleteResults() async throws {
    let calls = Mutex(0)
    let engine = FontFeaturePreviewEngine { feature, config in
      let cancel = calls.withLock { count in
        count += 1
        return count == 1
      }
      if cancel { withUnsafeCurrentTask { $0?.cancel() } }
      return FontFeaturePreview.make(feature: feature, config: config)
    }
    let config = FontConfiguration("HelveticaNeue")
    let cancelled = Task { try await engine.previews(config: config) }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(calls.withLock { $0 } == 1)
    let previews = try await engine.previews(config: config)
    #expect(previews["aat.1.2"] != nil)
    #expect(calls.withLock { $0 } == 1 + config.face.features.filter { !$0.isAutomatic }.count)
    let cached = try await engine.previews(config: config)
    #expect(cached["aat.1.2"]?.text == previews["aat.1.2"]?.text)
  }

  @Test(arguments: [
    ("HelveticaNeue", "aat.1.2"), ("ArialMT", "ot.liga"), ("ArialMT", "ot.dlig"),
  ])
  func ligatureExamplesActuallyFormLigatures(name: String, id: String) throws {
    let config = FontConfiguration(name)
    let feature = try #require(config.face.features.first { $0.id == id })
    let preview = try #require(FontFeaturePreview.make(feature: feature, config: config))
    #expect(FontRenderer.supports(preview.text, config: preview.before))
    #expect(FontRenderer.supports(preview.text, config: preview.after))
    let before = FontRenderer.line(preview.text, config: preview.before, size: 21)
    let after = FontRenderer.line(preview.text, config: preview.after, size: 21)
    #expect(CTLineGetGlyphCount(after) < CTLineGetGlyphCount(before))
    #expect(preview.before.postScriptName == name)
    #expect(preview.after.postScriptName == name)
  }

  @Test func alternatePunctuationChangesRealInkAndPreservesOtherSettings() throws {
    var config = FontConfiguration("HelveticaNeue")
    config.tracking = 0.02
    config.features["ot.kern"] = 0
    config.features["aat.17"] = 1
    let feature = try #require(config.face.features.first { $0.id == "aat.17" })
    let preview = try #require(FontFeaturePreview.make(feature: feature, config: config))
    #expect(preview.text == ".:")
    #expect(preview.before.tracking == config.tracking)
    #expect(preview.after.features["ot.kern"] == 0)
    #expect(preview.after.features["aat.17"] == 1)
    let before = FontRenderer.mask(
      preview.text, config: preview.before, size: 40, width: 100, height: 70,
      origin: .init(x: 10, y: 10))
    let after = FontRenderer.mask(
      preview.text, config: preview.after, size: 40, width: 100, height: 70,
      origin: .init(x: 10, y: 10))
    #expect(before != after)
  }

  @Test func kerningExamplesIncludePositioningChanges() throws {
    let config = FontConfiguration("HelveticaNeue")
    let feature = try #require(config.face.features.first { $0.id == "ot.kern" })
    let preview = try #require(FontFeaturePreview.make(feature: feature, config: config))
    #expect(
      FontRenderer.measure(preview.text, config: preview.before, size: 21).advance
        != FontRenderer.measure(preview.text, config: preview.after, size: 21).advance)
  }

  @Test func previewsRejectMissingFontsAndUnchangedExamples() throws {
    let config = FontConfiguration("ArialMT")
    let automatic = try #require(config.face.features.first { $0.isAutomatic })
    #expect(FontFeaturePreview.make(feature: automatic, config: config) == nil)
    let inert = FontFeature(
      id: "ot.test", name: "Unrecognized feature",
      options: [.init(name: "Off", value: 0), .init(name: "On", value: 1)], defaultValue: 0,
      sample: "🦄")
    #expect(FontFeaturePreview.make(feature: inert, config: config) == nil)
    #expect(
      FontFeaturePreview.make(feature: inert, config: .init("TypefaceOff-Does-Not-Exist")) == nil)
  }

  @Test(.enabled(if: FontCatalog().preferredFace(in: "Inter Variable") != nil))
  func characterVariantsPreferMetadataExamplesWhenTheyChange() throws {
    let face = try #require(FontCatalog().preferredFace(in: "Inter Variable"))
    var feature = try #require(face.features.first { $0.id == "ot.cv11" })
    feature.sample = "a"
    let preview = try #require(
      FontFeaturePreview.make(feature: feature, config: .init(face.id)))
    #expect(preview.text == feature.sample)
    #expect(Differences.compare("a", a: preview.before, b: preview.after).shape > 0.1)
  }
}
