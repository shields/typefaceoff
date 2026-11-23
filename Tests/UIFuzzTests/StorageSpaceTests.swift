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
import Testing

@testable import UIFuzzSupport

@Suite struct StorageSpaceTests {
  @Test func aFullVolumeStopsBeforeAnotherExecution() throws {
    let directory = URL(fileURLWithPath: "/full-volume")
    #expect(
      throws: StorageSpace.InsufficientSpace(
        directory: directory, availableBytes: 0, minimumBytes: 512)
    ) {
      try StorageSpace.require(at: directory, minimumBytes: 512, capacity: { _ in 0 })
    }
    try StorageSpace.require(at: directory, minimumBytes: 512, capacity: { _ in 512 })
    try StorageSpace.require(at: directory, minimumBytes: 512, capacity: { _ in 1024 })
    let error = StorageSpace.InsufficientSpace(
      directory: directory, availableBytes: 12, minimumBytes: 512)
    #expect(error.description.contains("/full-volume"))
    #expect(error.description.contains("12 bytes available"))
    #expect(error.description.contains("512 bytes required"))
  }

  @Test func anUnreadableCapacityFailsLoudly() {
    struct CapacityError: Error {}
    #expect(throws: CapacityError.self) {
      try StorageSpace.require(at: URL(fileURLWithPath: "/volume"), minimumBytes: 1) { _ in
        throw CapacityError()
      }
    }
  }

  @Test func capacityIsReadFromTheVolumeThatHoldsTheDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
    #expect(try StorageSpace.availableBytes(at: directory) > 0)
    try StorageSpace.require(at: directory, minimumBytes: 1)
    #expect(throws: (any Error).self) {
      try StorageSpace.availableBytes(at: directory.appending(path: UUID().uuidString))
    }
  }
}
