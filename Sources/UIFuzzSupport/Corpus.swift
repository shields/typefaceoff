import Foundation

public struct CoverageDelta: Equatable, Sendable {
  public var regions: Set<String>
  public var countBuckets: Set<String>

  public var isInteresting: Bool { !regions.isEmpty || !countBuckets.isEmpty }
}

public struct CorpusState: Codable, Equatable, Sendable {
  public var regions: Set<String> = []
  public var countBuckets: Set<String> = []
  public var executions = 0

  public init() {}

  public mutating func consider(regions: Set<String>, countBuckets: Set<String>) -> CoverageDelta {
    let delta = CoverageDelta(
      regions: regions.subtracting(self.regions),
      countBuckets: countBuckets.subtracting(self.countBuckets))
    self.regions.formUnion(regions)
    self.countBuckets.formUnion(countBuckets)
    executions += 1
    return delta
  }
}

public enum CoverageBuckets {
  /// The largest power of two not above `count`. A region that never ran has no bucket, so zero
  /// and negative counts map to 0.
  public static func bucket(_ count: Int) -> Int {
    guard count > 0 else { return 0 }
    return 1 << (Int.bitWidth - 1 - count.leadingZeroBitCount)
  }
}

public enum TraceReducer {
  public static func reduce(
    _ trace: FuzzTrace, reproduces: ([FuzzAction]) throws -> Bool
  ) rethrows -> FuzzTrace {
    var actions = trace.actions
    var chunk = max(1, actions.count / 2)
    while !actions.isEmpty, chunk >= 1 {
      var removed = false
      var start = 0
      while start < actions.count {
        let end = min(actions.count, start + chunk)
        var candidate = actions
        candidate.removeSubrange(start..<end)
        if try reproduces(candidate) {
          actions = candidate
          removed = true
        } else {
          start += chunk
        }
      }
      if chunk == 1 { break }
      if !removed { chunk = max(1, chunk / 2) }
    }
    var reduced = trace
    reduced.actions = actions
    reduced.origin = "minimized"
    return reduced
  }
}

public enum Statistics {
  public static func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
  }
}
