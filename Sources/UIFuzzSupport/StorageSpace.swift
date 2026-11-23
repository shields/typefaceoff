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
