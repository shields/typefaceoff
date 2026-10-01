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
