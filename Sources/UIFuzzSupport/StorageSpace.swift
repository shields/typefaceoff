import Foundation

public enum StorageSpace {
  public struct InsufficientSpace: Error, CustomStringConvertible, Equatable {
    public let directory: URL
    public let availableBytes: UInt64
    public let minimumBytes: UInt64

    public var description: String {
      "Insufficient disk space at \(directory.path): \(availableBytes) bytes available, "
        + "\(minimumBytes) bytes required. The campaign cannot continue."
    }
  }

  public static func require(
    at directory: URL, minimumBytes: UInt64,
    capacity: (URL) throws -> UInt64 = availableBytes
  ) throws {
    let available = try capacity(directory)
    guard available >= minimumBytes else {
      throw InsufficientSpace(
        directory: directory, availableBytes: available, minimumBytes: minimumBytes)
    }
  }

  public static func availableBytes(at directory: URL) throws -> UInt64 {
    let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
    return (attributes[.systemFreeSize] as! NSNumber).uint64Value
  }
}
