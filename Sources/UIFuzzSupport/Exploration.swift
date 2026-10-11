import Foundation

/// Balance input kinds before controls, so a long font list cannot crowd out other inputs.
public struct ActionExplorer {
  /// A control's identity for balancing. Named controls ignore their path, which drifts between
  /// discoveries, and are told apart by their order among identical names. Unnamed controls keep
  /// their path. Keyboard actions carry no target, so their key codes tell them apart.
  private struct VisitKey: Hashable {
    var kind: FuzzAction.Kind
    var role: String?
    var target: String?
    var ordinal = 0
    var path: [Int]?
    var keyCode: UInt16?
    var modifiers: UInt64?

    init(_ action: FuzzAction) {
      kind = action.kind
      role = action.targetRole
      target = action.target
      if action.target == nil { path = action.targetPath }
      keyCode = action.keyCode
      modifiers = action.modifiers
    }
  }

  private var kindVisits: [FuzzAction.Kind: Int] = [:]
  private var controlVisits: [VisitKey: Int] = [:]
  private var excluded: Set<String> = []
  private let mutator: TraceMutator

  public init(mutator: TraceMutator) { self.mutator = mutator }

  /// Visit counts carry over so balancing continues across a campaign's runs.
  public mutating func beginRun() { excluded.removeAll() }

  /// Keeps a control out of the rest of this run once it has failed to resolve. Every kind and
  /// every same-named duplicate of the control goes, matching `SkipLedger`'s per-run key.
  public mutating func exclude(_ action: FuzzAction) {
    precondition(action.kind.needsTarget)
    excluded.insert(Self.runKey(action))
  }

  public mutating func next(
    from available: [FuzzAction], using random: inout SplitMix64
  ) -> FuzzAction {
    guard !available.isEmpty else { return FuzzAction(kind: .key, keyCode: 53) }
    let keys = Self.visitKeys(available)
    var candidates = Array(available.indices)
    if !excluded.isEmpty {
      let offered = candidates.filter { !excluded.contains(Self.runKey(available[$0])) }
      if !offered.isEmpty { candidates = offered }
    }
    let kinds = Set(candidates.map { available[$0].kind }).sorted { $0.rawValue < $1.rawValue }
    let minimumKindVisits = kinds.map { kindVisits[$0, default: 0] }.min()!
    let leastUsedKinds = kinds.filter { kindVisits[$0, default: 0] == minimumKindVisits }
    let kind = leastUsedKinds[Int(random.next() % UInt64(leastUsedKinds.count))]
    let controls = candidates.filter { available[$0].kind == kind }
    let minimumControlVisits = controls.map { controlVisits[keys[$0], default: 0] }.min()!
    let leastUsedControls = controls.filter {
      controlVisits[keys[$0], default: 0] == minimumControlVisits
    }
    let index = leastUsedControls[Int(random.next() % UInt64(leastUsedControls.count))]
    var action = available[index]
    kindVisits[kind, default: 0] += 1
    controlVisits[keys[index], default: 0] += 1
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
      case "Search Unicode characters":
        let queries = [
          "", "arrow", "letter a", "left-arrow", "letf arrow", "U+2192", "u+1f984", "2192", "é",
          "e\u{301}", "→", "-", "👩‍🚀", "A", "U+E000", "zzzz",
        ]
        action.value = queries[Int(random.next() % UInt64(queries.count))]
      case "Custom specimen text":
        action.value = mutator.text(using: &random)
      case "Language search field", "Search languages", "Language query":
        let queries = [
          "", "English", "eng", "Latin", "العربية", "Japanese", "Ancient Greek", "zzzz",
        ]
        action.value = queries[Int(random.next() % UInt64(queries.count))]
      case "Language speaker field", "Minimum speaker count", "Minimum language speakers":
        let values = ["All", "100", "100K", "1M", "8.3M", "10M", "100M", "1B", "bad"]
        action.value = values[Int(random.next() % UInt64(values.count))]
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

  static let shortcuts: [(UInt16, UInt64)] = {
    let command: UInt64 = 1 << 20
    let shift: UInt64 = 1 << 17
    let option: UInt64 = 1 << 19
    return [
      (18, command), (19, command), (20, command), (18, command | shift), (19, command | shift),
      (18, command | option), (19, command | option), (6, command), (6, command | shift),
      (1, command | option), (14, command | shift), (45, command), (46, command | shift),
      (3, command),
    ]
  }()

  private static func runKey(_ action: FuzzAction) -> String {
    ResolutionRequest(action, allowVisibleTieBreak: false).runKey
  }

  private static func visitKeys(_ available: [FuzzAction]) -> [VisitKey] {
    var seen: [VisitKey: Int] = [:]
    return available.map { action in
      var key = VisitKey(action)
      guard action.target != nil else { return key }
      let ordinal = seen[key, default: 0]
      seen[key] = ordinal + 1
      key.ordinal = ordinal
      return key
    }
  }

  /// With a menu open, Return would activate whatever item the arrows highlighted, including an
  /// item that discovery does not offer, so `inMenu` leaves only Escape and the arrows.
  public static func keyboardActions(includeShortcuts: Bool, inMenu: Bool = false) -> [FuzzAction] {
    let codes: [UInt16] = inMenu ? [53, 123, 124, 125, 126] : [36, 48, 53, 123, 124, 125, 126]
    var result = codes.map { FuzzAction(kind: .key, keyCode: $0) }
    if includeShortcuts {
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
