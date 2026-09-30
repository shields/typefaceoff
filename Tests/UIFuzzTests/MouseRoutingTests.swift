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
