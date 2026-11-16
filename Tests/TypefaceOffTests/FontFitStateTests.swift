import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct FontFitStateTests {
  @Test func applyingAStreamingImprovementRequiresStoppingFirst() async throws {
    let model = WorkbenchModel()
    let initial = model.comparison
    let b = try #require(initial.b)
    let (stream, continuation) = AsyncThrowingStream<FontFitResult, Error>.makeStream()
    defer { continuation.finish() }
    let fit = FontFitModel { _, _ in stream }
    let host = WorkbenchTestHost(MatchSheet(model: model, fit: fit))
    defer { host.window.close() }
    try await host.press("Font B Optimize tracking")
    var proposal = b
    proposal.tracking = 0.025
    continuation.yield(
      .init(
        proposed: proposal, originalScore: SimilarityModelTests.score(0.5),
        score: SimilarityModelTests.score(0.4), evaluations: 1, finished: false))
    try await waitUntil { fit.result?.improved == true }
    #expect(fit.running && !host.isEnabled("Apply"))
    #expect(!fit.apply(to: model, undoManager: nil))
    #expect(model.comparison == initial)
    try await host.press("Stop")
    try await host.settle { host.isEnabled("Apply") }
    try await host.press("Apply")
    #expect(model.comparison.a == initial.a && model.comparison.b == proposal)
  }

  @Test func canonicallyEquivalentTextInvalidatesTheVerifiedPreview() async throws {
    let model = WorkbenchModel()
    model.comparison.sample = .custom
    model.comparison.customText = "é"
    let b = try #require(model.comparison.b)
    let request = FontFitModel.Request(
      a: model.comparison.a, b: b, text: model.comparison.text, options: .init(config: b), scale: 2)
    let fit = FontFitModel(load: SimilarityModelTests.fitResult)
    fit.start(request)
    try await waitUntil { !fit.running }
    #expect(fit.result?.improved == true)
    model.comparison.customText = "e\u{301}"
    #expect(!fit.apply(to: model, undoManager: nil))
    let next = FontFitModel.Request(
      a: request.a, b: b, text: model.comparison.text, options: request.options,
      scale: request.scale)
    #expect(request != next)
    #expect(!next.hasSameInputs(as: request))
    fit.start(next)
    #expect(fit.result == nil)
    try await waitUntil { !fit.running }
    #expect(fit.result?.evaluations == 10)
  }
}
