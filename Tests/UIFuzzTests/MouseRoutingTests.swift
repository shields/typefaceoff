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

@Suite struct MouseRoutingTests {
  @Test func hitTestResultsClassifyAgainstTheTargetProcess() {
    #expect(MouseRouting(hitProcess: 10, target: 10) == .target)
    #expect(MouseRouting(hitProcess: 11, target: 10) == .otherProcess)
  }

  @Test func onlyAnotherProcessOrABusyAppIsWorthWaitingOn() {
    #expect(MouseRouting.otherProcess.mayResolve)
    #expect(MouseRouting.unanswered.mayResolve)
    #expect(!MouseRouting.nothing.mayResolve)
    #expect(!MouseRouting.target.mayResolve)
  }

  @Test func eachRoutingHasItsOwnReasonBecauseReasonsBecomeFindingSignatures() {
    let reasons = [MouseRouting.target, .otherProcess, .nothing, .unanswered].map(\.reason)
    #expect(Set(reasons).count == 4)
  }
}
