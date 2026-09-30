import Testing

@MainActor func waitUntil(
  _ condition: () -> Bool, describing state: @autoclosure () -> String = "",
  sourceLocation: SourceLocation = #_sourceLocation
) async throws {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(condition(), "Timed out after 10 seconds. \(state())", sourceLocation: sourceLocation)
}
