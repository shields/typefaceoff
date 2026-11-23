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
