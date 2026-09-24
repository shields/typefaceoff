import Foundation

public struct SplitMix64: RandomNumberGenerator, Sendable {
  private var state: UInt64

  public init(seed: UInt64) { state = seed }

  public mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var value = state
    value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
    value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
    return value ^ (value >> 31)
  }
}

public struct TraceMutator: Sendable {
  public var maximumActions: Int
  public var maximumTextUnits: Int
  public var installedFontFamilies: [String]

  public init(
    maximumActions: Int = 512, maximumTextUnits: Int = 100_000,
    installedFontFamilies: [String] = []
  ) {
    self.maximumActions = maximumActions
    self.maximumTextUnits = maximumTextUnits
    self.installedFontFamilies = installedFontFamilies
  }

  public func mutate(_ input: FuzzTrace, seed: UInt64) -> FuzzTrace {
    var random = SplitMix64(seed: seed)
    var actions = constrained(input).actions
    let edits = 1 + Int(random.next() % 4)
    for _ in 0..<edits {
      switch random.next() % 4 {
      case 0 where !actions.isEmpty:
        actions.remove(at: Int(random.next() % UInt64(actions.count)))
      case 1 where !actions.isEmpty && actions.count < maximumActions:
        let index = Int(random.next() % UInt64(actions.count))
        actions.insert(actions[index], at: index)
      case 2 where !actions.isEmpty:
        actions[Int(random.next() % UInt64(actions.count))] = action(using: &random)
      default:
        guard actions.count < maximumActions else { continue }
        let index = Int(random.next() % UInt64(actions.count + 1))
        actions.insert(action(using: &random), at: index)
      }
    }
    if actions.isEmpty { actions.append(action(using: &random)) }
    return FuzzTrace(seed: seed, actions: actions, origin: "mutation")
  }

  public func initialCorpus(seed: UInt64) -> [FuzzTrace] {
    let command = UInt64(1 << 20)
    let shift = UInt64(1 << 17)
    let option = UInt64(1 << 19)
    let scenarios: [[FuzzAction]] = [
      [FuzzAction(kind: .shortcut, keyCode: 18, modifiers: command)],
      [FuzzAction(kind: .shortcut, keyCode: 19, modifiers: command)],
      [FuzzAction(kind: .setValue, target: "Shared point size", value: "44")],
      [
        FuzzAction(kind: .setValue, target: "Shared point size", value: "144"),
        FuzzAction(kind: .shortcut, keyCode: 6, modifiers: command),
        FuzzAction(kind: .shortcut, keyCode: 6, modifiers: command | shift),
      ],
      [FuzzAction(kind: .shortcut, keyCode: 1, modifiers: command | option)],
      [
        FuzzAction(kind: .press, target: "Match…", delayMilliseconds: 400),
        FuzzAction(kind: .press, target: "Tracking"),
        FuzzAction(kind: .press, target: "Cancel"),
      ],
      [
        FuzzAction(
          kind: .shortcut, keyCode: 14, modifiers: command | shift, delayMilliseconds: 400),
        FuzzAction(kind: .setValue, target: "Custom specimen text", value: "Hamburg 🦄 e\u{301}"),
        FuzzAction(kind: .press, target: "Apply", delayMilliseconds: 400),
      ],
      [
        FuzzAction(kind: .shortcut, keyCode: 19, modifiers: command),
        FuzzAction(kind: .setValue, target: "Character", value: "👩‍🚀"),
        FuzzAction(kind: .press, target: "Zoom in"),
        FuzzAction(kind: .key, keyCode: 124),
      ],
      [
        FuzzAction(kind: .press, target: "Font A family", delayMilliseconds: 400),
        FuzzAction(kind: .setValue, target: "Search installed fonts", value: "Helvetica"),
        FuzzAction(kind: .key, keyCode: 125),
        FuzzAction(kind: .key, keyCode: 36, delayMilliseconds: 400),
      ],
      [
        FuzzAction(kind: .increment, target: "Font A Size"),
        FuzzAction(kind: .increment, target: "Font A Tracking"),
      ],
      [FuzzAction(kind: .shortcut, keyCode: 45, modifiers: command)],
      [
        FuzzAction(kind: .shortcut, keyCode: 19, modifiers: command),
        FuzzAction(kind: .scroll, target: "Glyph canvas", deltaX: 0, deltaY: 40),
      ],
      [
        FuzzAction(kind: .shortcut, keyCode: 19, modifiers: command),
        FuzzAction(kind: .press, target: "Zoom in"),
        FuzzAction(kind: .drag, target: "Glyph canvas", deltaX: 40, deltaY: 25),
      ],
      [
        FuzzAction(kind: .shortcut, keyCode: 19, modifiers: command),
        FuzzAction(kind: .click, target: "Glyph canvas"),
      ],
    ]
    var result = scenarios.enumerated().map { index, actions in
      FuzzTrace(seed: seed &+ UInt64(index), actions: actions, origin: "seed")
    }
    result.append(
      FuzzTrace(
        seed: seed &+ UInt64(result.count),
        actions: [FuzzAction(kind: .selectFont, target: "Font B family", value: "None")],
        origin: "seed"))
    // Seed both sides without making startup proportional to the font registry.
    var random = SplitMix64(seed: seed)
    for side in ["A", "B"] where !installedFontFamilies.isEmpty {
      let family = installedFontFamilies[Int(random.next() % UInt64(installedFontFamilies.count))]
      result.append(
        FuzzTrace(
          seed: seed &+ UInt64(result.count),
          actions: [FuzzAction(kind: .selectFont, target: "Font \(side) family", value: family)],
          origin: "seed"))
    }
    return result.map(constrained)
  }

  public func constrained(_ input: FuzzTrace) -> FuzzTrace {
    var result = input
    result.actions = input.actions.prefix(max(0, maximumActions)).map { action in
      guard action.kind == .setValue, action.target == "Custom specimen text",
        let value = action.value
      else { return action }
      var bounded = action
      bounded.value = String(
        decoding: value.utf16.prefix(max(0, maximumTextUnits)), as: UTF16.self)
      return bounded
    }
    return result
  }

  private func action(using random: inout SplitMix64) -> FuzzAction {
    let settled = random.next() % 5 == 0
    let delay = settled ? 400 : [0, 5, 20, 50][Int(random.next() % 4)]
    switch random.next() % 13 {
    case 0:
      let targets = [
        "Swap fonts", "Match…", "Apply", "Cancel", "Weight", "Tracking",
        "Previous character", "Next character", "Zoom in", "Zoom out", "Reset glyph zoom",
        "Toggle font A inspector", "Toggle font B inspector", "Unlock appearance",
        "Lock appearance", "Edit text",
      ]
      return FuzzAction(
        kind: .press, target: targets[Int(random.next() % UInt64(targets.count))],
        delayMilliseconds: delay)
    case 1:
      let targets = [
        "Font A Size", "Font B Size", "Font A Tracking", "Font B Tracking", "Glyph zoom",
      ]
      return FuzzAction(
        kind: random.next().isMultiple(of: 2) ? .increment : .decrement,
        target: targets[Int(random.next() % UInt64(targets.count))], delayMilliseconds: delay)
    case 2:
      let values = ["10", "22", "144", "10.001", "143.999", "−1", "nan", "1e9"]
      return FuzzAction(
        kind: .setValue, target: "Shared point size",
        value: values[Int(random.next() % UInt64(values.count))], delayMilliseconds: delay)
    case 3:
      let glyphs = ["a", "@", "Á", "e\u{301}", "🦄", "👩‍🚀", " ", "\u{0000}"]
      return FuzzAction(
        kind: .setValue, target: "Character",
        value: glyphs[Int(random.next() % UInt64(glyphs.count))], delayMilliseconds: delay)
    case 4:
      return FuzzAction(
        kind: .setValue, target: "Custom specimen text", value: text(using: &random),
        delayMilliseconds: delay)
    case 5:
      let shortcuts: [(UInt16, UInt64)] = [
        (18, 1 << 20), (19, 1 << 20), (18, (1 << 20) | (1 << 17)),
        (19, (1 << 20) | (1 << 17)), (18, (1 << 20) | (1 << 19)),
        (19, (1 << 20) | (1 << 19)), (6, 1 << 20), (6, (1 << 20) | (1 << 17)),
        (1, (1 << 20) | (1 << 19)), (14, (1 << 20) | (1 << 17)), (45, 1 << 20),
        (13, 1 << 20),
      ]
      let shortcut = shortcuts[Int(random.next() % UInt64(shortcuts.count))]
      return FuzzAction(
        kind: .shortcut, keyCode: shortcut.0, modifiers: shortcut.1,
        delayMilliseconds: delay)
    case 6:
      return FuzzAction(
        kind: .key, keyCode: random.next().isMultiple(of: 2) ? 123 : 124,
        delayMilliseconds: delay)
    case 7:
      let targets = ["Glyph canvas", "Font A specimen", "Font B specimen"]
      return FuzzAction(
        kind: .scroll, target: targets[Int(random.next() % UInt64(targets.count))],
        deltaX: Double(Int64(random.next() % 21) - 10),
        deltaY: Double(Int64(random.next() % 81) - 40), delayMilliseconds: delay)
    case 8:
      return FuzzAction(
        kind: .pause, delayMilliseconds: [1, 30, 119, 121, 500][Int(random.next() % 5)])
    case 9:
      let targets = ["Glyph canvas", "Font A specimen", "Font B specimen"]
      return FuzzAction(
        kind: .click,
        target: targets[Int(random.next() % UInt64(targets.count))],
        delayMilliseconds: delay)
    case 10:
      return FuzzAction(
        kind: .drag, target: "Glyph canvas",
        deltaX: Double(Int64(random.next() % 121) - 60),
        deltaY: Double(Int64(random.next() % 121) - 60), delayMilliseconds: delay)
    case 11 where !installedFontFamilies.isEmpty:
      return FuzzAction(
        kind: .selectFont,
        target: random.next().isMultiple(of: 2) ? "Font A family" : "Font B family",
        value: installedFontFamilies[Int(random.next() % UInt64(installedFontFamilies.count))],
        delayMilliseconds: max(delay, 400))
    default:
      return FuzzAction(
        kind: .press, target: random.next().isMultiple(of: 2) ? "Shape" : "Spacing",
        delayMilliseconds: delay)
    }
  }

  func text(using random: inout SplitMix64) -> String {
    let units = [0, 1, 16, 256, 4096, maximumTextUnits]
      .map { min($0, maximumTextUnits) }[Int(random.next() % 6)]
    guard units > 0 else { return "" }
    let fragments = ["Hamburg ", "fi fl ", "e\u{301} ", "🦄 ", "👩‍🚀 ", "\n\n"]
    var result = ""
    while result.utf16.count < units {
      result += fragments[Int(random.next() % UInt64(fragments.count))]
    }
    return String(decoding: result.utf16.prefix(units), as: UTF16.self)
  }
}
