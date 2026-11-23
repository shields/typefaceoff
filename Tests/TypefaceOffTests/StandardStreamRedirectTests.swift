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
import Testing

@testable import TypefaceOff

@Suite struct StandardStreamRedirectTests {
  private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "stream-redirect-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// A stream that stands in for stdout so the process's real output is left alone.
  private func makeStream(in directory: URL) throws -> UnsafeMutablePointer<FILE> {
    try #require(fopen(directory.appending(path: "original").path, "w"))
  }

  @Test func lineBufferedOutputReachesTheFileBeforeTheStreamIsFlushed() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let stream = try makeStream(in: directory)
    defer { fclose(stream) }
    let log = directory.appending(path: "stdout.log")

    try StandardStreamRedirect.append(stream, to: log, buffering: _IOLBF)
    fputs("first line\nsecond ", stream)

    #expect(try String(contentsOf: log, encoding: .utf8) == "first line\n")
  }

  @Test func unbufferedOutputReachesTheFileImmediately() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let stream = try makeStream(in: directory)
    defer { fclose(stream) }
    let log = directory.appending(path: "stderr.log")

    try StandardStreamRedirect.append(stream, to: log, buffering: _IONBF)
    fputs("no newline", stream)

    #expect(try String(contentsOf: log, encoding: .utf8) == "no newline")
  }

  @Test func outputAppendsToWhatTheFileAlreadyHolds() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let stream = try makeStream(in: directory)
    defer { fclose(stream) }
    let log = directory.appending(path: "stdout.log")
    try Data("earlier\n".utf8).write(to: log)

    fputs("buffered before the redirect\n", stream)
    try StandardStreamRedirect.append(stream, to: log, buffering: _IOLBF)
    fputs("later\n", stream)

    #expect(try String(contentsOf: log, encoding: .utf8) == "earlier\nlater\n")
    #expect(
      try String(contentsOf: directory.appending(path: "original"), encoding: .utf8)
        == "buffered before the redirect\n")
  }

  @Test func aFileThatCannotBeOpenedFailsLoudly() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let stream = try makeStream(in: directory)
    defer { fclose(stream) }

    let error = #expect(throws: NSError.self) {
      try StandardStreamRedirect.append(
        stream, to: directory.appending(path: "missing/stdout.log"), buffering: _IOLBF)
    }
    #expect(error?.domain == NSPOSIXErrorDomain)
    #expect(error?.code == Int(ENOENT))
  }
}
