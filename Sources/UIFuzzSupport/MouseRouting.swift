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

/// Where WindowServer will deliver a synthesized mouse event, judged from the Accessibility hit
/// test at the event's location (`AXUIElementCopyElementAtPosition`, then the element's process).
public enum MouseRouting: Equatable, Sendable {
  case target
  /// An element of another process is under the point: the Dock or another app's window.
  case otherProcess
  /// No element is under the point: it is off every display, or in a gap.
  case nothing
  /// Accessibility timed out, as it does while the app is busy, so the hit test says nothing.
  case unanswered

  public init(hitProcess: Int32, target: Int32) {
    self = hitProcess == target ? .target : .otherProcess
  }

  /// Activation raises the app's windows a moment after AXFrontmost turns true, so another
  /// process under the point may go away, and a busy app may answer later.
  public var mayResolve: Bool {
    switch self {
    case .otherProcess, .unanswered: true
    case .target, .nothing: false
    }
  }

  /// Fixed text, because a failing action's description becomes its finding's signature.
  public var reason: String {
    switch self {
    case .target: "the app is under the point"
    case .otherProcess: "another app is under the point"
    case .nothing: "nothing is under the point"
    case .unanswered: "Accessibility did not answer"
    }
  }
}
