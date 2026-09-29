import AppKit
import UIFuzzSupport

extension NSRunningApplication {
  var hasExited: Bool { !ProcessLiveness.isAlive(processIdentifier) }
}
