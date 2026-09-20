import Foundation

/// Balance input kinds before controls, so a long font list cannot crowd out other inputs.
public struct ActionExplorer {
  private var kindVisits: [FuzzAction.Kind: Int] = [:]
  private var controlVisits: [FuzzAction: Int] = [:]
  private let mutator: TraceMutator

  public init(mutator: TraceMutator) { self.mutator = mutator }

  public mutating func next(
    from available: [FuzzAction], using random: inout SplitMix64
  ) -> FuzzAction {
    guard !available.isEmpty else { return FuzzAction(kind: .key, keyCode: 53) }
    let kinds = Set(available.map(\.kind)).sorted { $0.rawValue < $1.rawValue }
    let minimumKindVisits = kinds.map { kindVisits[$0, default: 0] }.min()!
    let leastUsedKinds = kinds.filter { kindVisits[$0, default: 0] == minimumKindVisits }
    let kind = leastUsedKinds[Int(random.next() % UInt64(leastUsedKinds.count))]
    let controls = available.filter { $0.kind == kind }
    let minimumControlVisits = controls.map { controlVisits[$0, default: 0] }.min()!
    let leastUsedControls = controls.filter {
      controlVisits[$0, default: 0] == minimumControlVisits
    }
    var action = leastUsedControls[Int(random.next() % UInt64(leastUsedControls.count))]
    kindVisits[kind, default: 0] += 1
    controlVisits[action, default: 0] += 1
    action.delayMilliseconds = [20, 50, 150, 400][Int(random.next() % 4)]
    switch kind {
    case .setValue:
      switch action.target {
      case "Search installed fonts":
        let queries = ["", "no-such-font", "a"] + mutator.installedFontFamilies
        action.value = queries[Int(random.next() % UInt64(queries.count))]
      case "Character":
        let glyphs = ["a", "@", "Á", "e\u{301}", "🦄", "👩‍🚀", " "]
        action.value = glyphs[Int(random.next() % UInt64(glyphs.count))]
      case "Custom specimen text":
        action.value = mutator.text(using: &random)
      default:
        let values = ["", "0", "10", "22", "144", "−1", "0.001", "nan", "1e9"]
        action.value = values[Int(random.next() % UInt64(values.count))]
      }
    case .scroll, .drag:
      action.deltaX = Double(Int(random.next() % 121) - 60)
      action.deltaY = Double(Int(random.next() % 241) - 120)
    default:
      break
    }
    return action
  }

  public static func keyboardActions(includeShortcuts: Bool) -> [FuzzAction] {
    var result: [FuzzAction] = [36, 48, 53, 123, 124, 125, 126].map {
      FuzzAction(kind: .key, keyCode: $0)
    }
    if includeShortcuts {
      let command: UInt64 = 1 << 20
      let shift: UInt64 = 1 << 17
      let option: UInt64 = 1 << 19
      let shortcuts: [(UInt16, UInt64)] = [
        (18, command), (19, command), (18, command | shift), (19, command | shift),
        (18, command | option), (19, command | option), (6, command), (6, command | shift),
        (1, command | option), (14, command | shift), (46, command | shift), (45, command),
      ]
      result += shortcuts.map { FuzzAction(kind: .shortcut, keyCode: $0.0, modifiers: $0.1) }
    }
    return result
  }
}

extension TraceMutator {
  /// Always explore on alternate executions, including campaigns with an old font-heavy corpus.
  public func campaignTrace(execution: Int, corpus: [FuzzTrace], seed: UInt64) -> FuzzTrace {
    if execution.isMultiple(of: 2) { return FuzzTrace(seed: seed, origin: "exploration") }
    let seeds = initialCorpus(seed: seed)
    let index = execution / 2
    if index < seeds.count { return seeds[index] }
    var random = SplitMix64(seed: seed)
    // Keep the current, balanced seeds represented even if the saved corpus is very skewed.
    let bases = corpus.isEmpty || random.next().isMultiple(of: 2) ? seeds : corpus
    return mutate(bases[Int(random.next() % UInt64(bases.count))], seed: random.next())
  }
}
