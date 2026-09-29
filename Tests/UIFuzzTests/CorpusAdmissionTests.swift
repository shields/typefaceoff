import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct CorpusAdmissionTests {
  private let actions = [
    FuzzAction(kind: .press, target: "One"), FuzzAction(kind: .press, target: "Two"),
    FuzzAction(kind: .press, target: "Missing"),
  ]

  private func report(
    completed: Int, findings: [ExecutionFinding.Kind], actions overridden: [FuzzAction]? = nil
  ) -> ExecutionReport {
    ExecutionReport(
      trace: FuzzTrace(seed: 7, actions: overridden ?? actions, origin: "exploration"),
      startedAt: Date(timeIntervalSince1970: 1), durationMilliseconds: 10,
      actionMilliseconds: Array(repeating: 1, count: completed),
      findings: findings.map { ExecutionFinding(kind: $0, signature: "s", detail: "d") })
  }

  @Test func aRunThatCompletedEveryActionKeepsItsWholeTrace() {
    for findings: [ExecutionFinding.Kind] in [
      [], [.automation], [.crash], [.hang, .automation], [.correctness],
    ] {
      let complete = report(completed: 3, findings: findings)
      #expect(CorpusAdmission.trace(for: complete) == complete.trace)
    }
  }

  @Test func aHarnessFailureOmitsTheActionThatNeverRan() throws {
    let failed = report(completed: 2, findings: [.automation])
    let admitted = try #require(CorpusAdmission.trace(for: failed))
    #expect(admitted.actions == Array(actions.prefix(2)))
    #expect(admitted.seed == failed.trace.seed)
    #expect(admitted.origin == failed.trace.origin)
    #expect(failed.trace.actions.count == 3)
  }

  @Test func aHarnessFailureOnTheFirstActionAdmitsNothing() {
    #expect(CorpusAdmission.trace(for: report(completed: 0, findings: [.automation])) == nil)
  }

  @Test func productFailuresKeepTheActionThatMayHaveCausedThem() {
    for kind: ExecutionFinding.Kind in [.crash, .hang, .correctness] {
      let failed = report(completed: 2, findings: [.automation, kind])
      #expect(CorpusAdmission.trace(for: failed) == failed.trace)
    }
  }

  @Test func anIncompleteRunWithoutAHarnessFailureKeepsItsWholeTrace() {
    let unavailable = report(completed: 2, findings: [.unavailable])
    #expect(CorpusAdmission.trace(for: unavailable) == unavailable.trace)
  }

  @Test func aRunWithNoActionsIsUnchanged() {
    let empty = report(completed: 0, findings: [.automation], actions: [])
    #expect(CorpusAdmission.trace(for: empty) == empty.trace)
  }
}
