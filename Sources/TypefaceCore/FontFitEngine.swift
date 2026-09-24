import Foundation

/// Mixed categorical/continuous search. Only full-corpus improvements are published.
public actor FontFitEngine {
  private struct Key: Equatable {
    let a: FontConfiguration
    let b: FontConfiguration
    let options: FontFitOptions
    let corpus: SimilarityCorpus
    let scale: Double
  }
  private struct Node {
    let config: FontConfiguration
    let value: Double
    let step: Double
  }
  private struct Expansion: Hashable {
    let config: FontConfiguration
    let step: Double
  }
  private struct Candidate {
    let config: FontConfiguration
    let step: Double
    let verify: Bool
  }
  private struct State {
    let key: Key
    let original: SimilarityScore
    var best: FontConfiguration
    var score: SimilarityScore
    var bestScreen: Double = .infinity
    var evaluations = 1
    var pending: [Candidate] = []
    var cursor = 0
    var categoricalPending: [Candidate] = []
    var categoricalCursor = 0
    var categoricalTurn = false
    var beam: [Node] = []
    var expanded = Set<Expansion>()
    var screened: [FontConfiguration: Double] = [:]
    var verified: [FontConfiguration: SimilarityScore] = [:]
    var priority: [String] = []
    var categories: [String] = []
    var categoryCursor = 0

    func result(finished: Bool) -> FontFitResult {
      FontFitResult(
        proposed: best, originalScore: original, score: score,
        evaluations: evaluations, finished: finished)
    }
  }

  private let evaluate:
    @Sendable (FontConfiguration, FontConfiguration, SimilarityCorpus, Double) async throws ->
      SimilarityScore
  private var saved: State?
  private var generation = UUID()

  public init(similarity: FontSimilarityEngine = .shared) {
    evaluate = { try await similarity.compare(a: $0, b: $1, corpus: $2, scale: $3) }
  }

  init(
    evaluate:
      @escaping @Sendable (FontConfiguration, FontConfiguration, SimilarityCorpus, Double)
      async throws -> SimilarityScore
  ) {
    self.evaluate = evaluate
  }

  public func fit(
    a: FontConfiguration, b: FontConfiguration, options: FontFitOptions,
    corpus: SimilarityCorpus, catalog: FontCatalog, scale: Double = 2,
    budget: FontFitBudget = .quick, refine: Bool = false
  ) -> AsyncThrowingStream<FontFitResult, Error> {
    let request = UUID()
    generation = request
    let key = Key(a: a, b: b, options: options, corpus: corpus, scale: scale)
    return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        do {
          try await run(
            key: key, catalog: catalog, budget: budget, refine: refine, request: request,
            continuation: continuation)
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func run(
    key: Key, catalog: FontCatalog, budget: FontFitBudget, refine: Bool, request: UUID,
    continuation: AsyncThrowingStream<FontFitResult, Error>.Continuation
  ) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(budget.seconds))
    let domain = FontFitDomain(original: key.b, options: key.options)
    let initialEvaluations: Int
    var state: State
    if refine, let previous = saved, previous.key == key {
      state = previous
      initialEvaluations = previous.evaluations
    } else {
      initialEvaluations = 0
      let initial = try await evaluate(key.a, key.b, key.corpus, key.scale)
      try check(request)
      state = State(key: key, original: initial, best: key.b, score: initial)
      state.verified[key.b] = initial
      let categorical = domain.categoricalSeeds()
      if categorical.count > 1 {
        state.categories = Array(Set((categorical + [key.b]).map { domain.category($0) })).sorted()
      }
      state.pending = seeds(domain: domain, reference: key.a, corpus: key.corpus, catalog: catalog)
        .map {
          Candidate(config: $0, step: 0.25, verify: true)
        }
      state.priority = domain.priority(text: key.corpus.requiredText)
    }
    continuation.yield(state.result(finished: false))
    while !key.options.isEmpty, state.score.total > SimilarityScore.improvementTolerance,
      state.evaluations - initialEvaluations < budget.evaluations, ContinuousClock.now < deadline
    {
      try check(request)
      if state.cursor >= state.pending.count {
        // Interleave short feature batches with axis refinement so a large feature
        // neighborhood cannot consume the budget before the step size decreases.
        if state.categoricalTurn || state.beam.isEmpty,
          state.categoricalCursor < state.categoricalPending.count
        {
          let end = min(state.categoricalCursor + 4, state.categoricalPending.count)
          state.pending = Array(state.categoricalPending[state.categoricalCursor..<end])
          state.categoricalCursor = end
          state.cursor = 0
          state.categoricalTurn = false
          continue
        }
        guard !state.beam.isEmpty else { break }
        var next = 0
        // Small categorical spaces get a continuous search in every legal state,
        // round-robin within the budget. Larger spaces share a beam of eight.
        for _ in state.categories.indices {
          let category = state.categories[state.categoryCursor % state.categories.count]
          state.categoryCursor += 1
          if let index = state.beam.firstIndex(where: { domain.category($0.config) == category }) {
            next = index
            break
          }
        }
        let node = state.beam.remove(at: next)
        guard node.step >= 1.0 / 1024,
          state.expanded.insert(Expansion(config: node.config, step: node.step)).inserted
        else { continue }
        let neighbors = domain.neighbors(node.config, step: node.step, priority: state.priority)
        if domain.dimensions.isEmpty {
          state.pending = neighbors.map { Candidate(config: $0, step: node.step, verify: false) }
        } else {
          state.pending = neighbors.filter { $0.features == node.config.features }.map {
            Candidate(config: $0, step: node.step, verify: false)
          }
          if state.categoricalCursor >= state.categoricalPending.count {
            state.categoricalPending = neighbors.filter { $0.features != node.config.features }.map
            {
              Candidate(config: $0, step: node.step, verify: true)
            }
            state.categoricalCursor = 0
          }
          state.categoricalTurn = true
        }
        state.cursor = 0
        state.beam.append(Node(config: node.config, value: node.value, step: node.step / 2))
        continue
      }
      let candidate = state.pending[state.cursor]
      state.cursor += 1
      let screen: Double
      if let cached = state.screened[candidate.config] {
        screen = cached
      } else {
        state.evaluations += 1
        do {
          screen = try await evaluate(key.a, candidate.config, key.corpus.screening, key.scale)
            .total
        } catch is SimilarityError {
          state.screened[candidate.config] = .infinity
          continue
        }
        try check(request)
        state.screened[candidate.config] = screen
      }
      guard screen.isFinite else { continue }
      if candidate.config == state.best { state.bestScreen = screen }
      if !state.beam.contains(where: { $0.config == candidate.config && $0.step == candidate.step })
      {
        state.beam.append(Node(config: candidate.config, value: screen, step: candidate.step))
        state.beam.sort {
          $0.value == $1.value
            ? FontFitDomain.order($0.config) < FontFitDomain.order($1.config) : $0.value < $1.value
        }
        if state.categories.isEmpty {
          state.beam = Array(state.beam.prefix(8))
        } else {
          var counts: [String: Int] = [:]
          state.beam = state.beam.filter {
            let category = domain.category($0.config)
            let count = counts[category, default: 0] + 1
            counts[category] = count
            return count <= 8
          }
        }
      }
      if state.verified[candidate.config] == nil,
        candidate.verify || candidate.config.features != state.best.features
          || screen < state.bestScreen - SimilarityScore.improvementTolerance
      {
        guard state.evaluations - initialEvaluations < budget.evaluations,
          ContinuousClock.now < deadline
        else {
          state.cursor -= 1  // Refine resumes the pending full-corpus validation.
          break
        }
        state.evaluations += 1
        do {
          let score = try await evaluate(key.a, candidate.config, key.corpus, key.scale)
          try check(request)
          state.verified[candidate.config] = score
          if score.total < state.score.total - SimilarityScore.improvementTolerance {
            state.best = candidate.config
            state.score = score
            state.bestScreen = screen
            continuation.yield(state.result(finished: false))
          }
        } catch is SimilarityError { continue }
      }
      saved = state
    }
    try check(request)
    saved = state
    continuation.yield(state.result(finished: true))
  }

  private func check(_ request: UUID) throws {
    try Task.checkCancellation()
    if request != generation { throw CancellationError() }
  }

  private func seeds(
    domain: FontFitDomain, reference: FontConfiguration, corpus: SimilarityCorpus,
    catalog: FontCatalog
  ) -> [FontConfiguration] {
    let b = domain.original
    var defaults = FontConfiguration(b.postScriptName)
    defaults.axes = Dictionary(uniqueKeysWithValues: b.face.axes.map { ($0.id, $0.defaultValue) })
    var matched = MatchOptions()
    matched.weight = domain.options.axes.contains(tagNumber("wght"))
    matched.xHeight = domain.options.size
    matched.tracking = domain.options.tracking
    var comparison = Comparison(a: reference, b: b)
    comparison.sample = .custom
    comparison.customText =
      corpus.requiredText.isEmpty ? corpus.runs.joined(separator: " ") : corpus.requiredText
    var result = [b]
    if let legacy = Matching.proposal(comparison, options: matched, catalog: catalog) {
      result.append(domain.constrained(legacy))
    }
    result.append(domain.constrained(defaults))
    for face in catalog.faces(in: b.face.family)
    where Set(face.axes.map(\.id)) == Set(b.face.axes.map(\.id)) {
      result.append(domain.constrained(FontConfiguration(face.id)))
    }
    // Sample several basins without transferring font-specific axis values from A.
    for fraction in [0.25, 0.5, 0.75] {
      var config = b
      for dimension in domain.dimensions {
        config = dimension.setting(
          config,
          value: dimension.range.lowerBound + fraction
            * (dimension.range.upperBound - dimension.range.lowerBound))
      }
      result.append(config)
    }
    result += domain.categoricalSeeds()
    var seen = Set<FontConfiguration>()
    return result.filter { seen.insert($0).inserted }
  }
}
