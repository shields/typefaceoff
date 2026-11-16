import Foundation
import Testing

@testable import UIFuzzSupport

@Suite struct SpecimenSubmissionTests {
  @Test func theEditorSeedIsOneIndivisibleSubmission() {
    let action = TraceMutator().initialCorpus(seed: 1)[6].actions
    #expect(
      action == [
        FuzzAction(kind: .setSpecimen, value: "Hamburg 🦄 e\u{301}", delayMilliseconds: 400)
      ])
    #expect(!action[0].kind.needsTarget)
  }

  @Test func generatedAndInheritedSubmissionsRespectTheUTF16Limit() {
    let mutator = TraceMutator(maximumTextUnits: 4)
    let inherited = FuzzTrace(
      seed: 1, actions: [FuzzAction(kind: .setSpecimen, value: "🦄🦄x")])
    #expect(mutator.constrained(inherited).actions[0].value == "🦄🦄")
    let actions = (0..<1000).flatMap { mutator.mutate(inherited, seed: UInt64($0)).actions }
    let submissions = actions.filter { $0.kind == .setSpecimen }
    #expect(!submissions.isEmpty)
    #expect(submissions.allSatisfy { ($0.value ?? "").utf16.count <= 4 })
  }

  @Test func aSubmissionClosesOverlaysBeforeTheNextControlRequirement() {
    var state = WorkbenchState.unknown
    let submission = FuzzAction(kind: .setSpecimen, value: "new specimen")
    state.apply(submission)
    #expect(state.operation == .closed)
    #expect(state.popover == .closed)
    let trace = TraceMutator().repaired([
      FuzzAction(kind: .press, target: "Match…"), submission,
      FuzzAction(kind: .setValue, target: "Custom specimen text", value: "next edit"),
    ])
    #expect(trace[1].kind == .key && trace[1].keyCode == 53)
    #expect(trace[2] == submission)
    #expect(trace[3].kind == .shortcut && trace[3].keyCode == 14)
  }

  @Test func compoundActionsRoundTripWithoutRecordedControlPaths() throws {
    let action = FuzzAction(kind: .setSpecimen, value: "e\u{301}\n🦄")
    let data = try JSONEncoder().encode(action)
    #expect(try JSONDecoder().decode(FuzzAction.self, from: data) == action)
  }
}
