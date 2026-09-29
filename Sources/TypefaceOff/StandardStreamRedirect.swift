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
