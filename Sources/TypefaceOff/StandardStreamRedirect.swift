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

import Darwin
import Foundation

/// Sends a C standard stream to a file. LaunchServices starts the app with no stdio of its own,
/// so a fuzz build redirects the streams itself.
enum StandardStreamRedirect {
  /// `buffering` is a `setvbuf` mode. Anything still in a full buffer when the process crashes
  /// is lost, so output that must survive a crash is line-buffered or unbuffered.
  static func append(
    _ stream: UnsafeMutablePointer<FILE>, to url: URL, buffering: Int32
  ) throws {
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    try check(descriptor)
    defer { if descriptor != fileno(stream) { close(descriptor) } }
    fflush(stream)
    try check(dup2(descriptor, fileno(stream)))
    setvbuf(stream, nil, buffering, 0)
  }

  private static func check(_ result: Int32) throws {
    if result < 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
  }
}
