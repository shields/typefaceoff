import Testing

@testable import UIFuzzSupport

@Suite struct CoverageBucketTests {
  @Test func bucketIsTheLargestPowerOfTwoNotAboveTheCount() {
    for shift in 0..<Int.bitWidth - 1 {
      let power = 1 << shift
      #expect(CoverageBuckets.bucket(power) == power)
      #expect(CoverageBuckets.bucket(power + power / 2) == power)
      #expect(CoverageBuckets.bucket(power &* 2 &- 1) == power)
    }
    #expect(CoverageBuckets.bucket(Int.max) == 1 << (Int.bitWidth - 2))
  }

  @Test func bucketAgreesWithAPlainDoublingLoop() {
    func doubling(_ count: Int) -> Int {
      var bucket = 1
      while bucket <= count / 2 { bucket *= 2 }
      return bucket
    }
    for count in 1...5000 { #expect(CoverageBuckets.bucket(count) == doubling(count)) }
    for shift in 12..<62 {
      for count in [(1 << shift) - 1, 1 << shift, (1 << shift) + 1] {
        #expect(CoverageBuckets.bucket(count) == doubling(count))
      }
    }
  }

  @Test func regionsThatNeverRanHaveNoBucket() {
    #expect(CoverageBuckets.bucket(0) == 0)
    #expect(CoverageBuckets.bucket(-1) == 0)
    #expect(CoverageBuckets.bucket(Int.min) == 0)
  }
}
