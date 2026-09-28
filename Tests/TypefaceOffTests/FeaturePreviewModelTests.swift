import Synchronization
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct FeaturePreviewModelTests {
  @Test(arguments: [false, true])
  func cancelledRequestsAvoidTheSearch(afterInitialRequest: Bool) async {
    let calls = Mutex(0)
    let model = FeaturePreviewModel { _ in
      calls.withLock { $0 += 1 }
      return [:]
    }
    if afterInitialRequest { await model.update(.init("ArialMT")) }
    let task = Task { await model.update(.init("HelveticaNeue")) }
    task.cancel()
    await task.value
    #expect(calls.withLock { $0 } == (afterInitialRequest ? 1 : 0))
    #expect(model.result == nil)
  }

  @Test(arguments: [false, true])
  func obsoleteResultsCannotReplaceTheCurrentFont(cancel: Bool) async {
    let (requests, started) = AsyncStream<FontConfiguration>.makeStream()
    let loader = SuspendedPreviewSearch(started: started)
    let model = FeaturePreviewModel { await loader.load($0) }
    var iterator = requests.makeAsyncIterator()
    let a = FontConfiguration("HelveticaNeue")
    let b = FontConfiguration("ArialMT")
    let old = Task { await model.update(a) }
    #expect(await iterator.next() == a)
    if cancel { old.cancel() }
    let current = Task { await model.update(b) }
    #expect(await iterator.next() == b)
    #expect(model.result == nil)
    await loader.finish(b)
    await current.value
    #expect(model.result?.config == b)
    await loader.finish(a)
    await old.value
    #expect(model.result?.config == b)
    await model.update(nil)
    #expect(model.result == nil)
  }
}

private actor SuspendedPreviewSearch {
  let started: AsyncStream<FontConfiguration>.Continuation
  var pending: [FontConfiguration: CheckedContinuation<[String: FontFeaturePreview], Never>] = [:]

  init(started: AsyncStream<FontConfiguration>.Continuation) { self.started = started }

  func load(_ config: FontConfiguration) async -> [String: FontFeaturePreview] {
    await withCheckedContinuation {
      pending[config] = $0
      started.yield(config)
    }
  }

  func finish(_ config: FontConfiguration) {
    pending.removeValue(forKey: config)?.resume(returning: [:])
  }
}
