import CoreText
import Foundation

public struct InventoryCoverage: Sendable {
  public let required: Int
  public let missing: [LanguageRequirement]
  public var covered: Int { required - missing.count }
  public var complete: Bool { missing.isEmpty }
}

public struct OrthographyCoverage: Sendable {
  public let categories: [LanguageCategory: InventoryCoverage]
  public var complete: Bool { categories[.base]!.complete }
}

public struct LanguageCoverage: Sendable {
  public let available: Bool
  public let orthographies: [String: OrthographyCoverage]

  public func completeScripts(_ language: LanguageRecord) -> [String] {
    guard available else { return [] }
    let eligible = language.orthographies.filter { language.historical || !$0.historical }
    let grouped = eligible.filter(\.grouped)
    let groupComplete = !grouped.isEmpty && grouped.allSatisfy { orthographies[$0.id]!.complete }
    return eligible.filter {
      $0.grouped ? groupComplete : orthographies[$0.id]!.complete
    }.map(\.script)
  }

  public func complete(_ language: LanguageRecord) -> Bool {
    !completeScripts(language).isEmpty
  }
}

public enum LanguageCoverageFilter: String, CaseIterable, Sendable {
  case all = "All"
  case both = "Both"
  case aOnly = "A only"
  case bOnly = "B only"
  case neither = "Neither"
  case covered = "Covered"
  case incomplete = "Incomplete"

  public static func options(comparing: Bool) -> [Self] {
    comparing ? [.all, .both, .aOnly, .bOnly, .neither] : [.all, .covered, .incomplete]
  }

  public func includes(a: Bool?, b: Bool?) -> Bool {
    switch self {
    case .all: return true
    case .covered: return a == true
    case .incomplete: return a == false
    case .both: return a == true && b == true
    case .aOnly: return a == true && b == false
    case .bOnly: return a == false && b == true
    case .neither: return a == false && b == false
    }
  }
}

public actor LanguageCoverageEngine {
  public static let shared = LanguageCoverageEngine()

  private struct CachedFont {
    var probes: [LanguageRequirement: Bool] = [:]
    var languages: [String: LanguageCoverage] = [:]
  }

  private var cache: [FontConfiguration: CachedFont] = [:]
  private var recent: [FontConfiguration] = []
  var cachedConfigurationCount: Int { cache.count }
  var probeCount: Int { cache.values.reduce(0) { $0 + $1.probes.count } }

  public init() {}

  public static func key(_ config: FontConfiguration) -> FontConfiguration {
    var key = config
    key.leading = nil
    key.tracking = 0
    return key
  }

  private func touch(_ key: FontConfiguration) {
    recent.removeAll { $0 == key }
    recent.append(key)
    if recent.count > 4 { cache.removeValue(forKey: recent.removeFirst()) }
    if cache[key] == nil { cache[key] = CachedFont() }
  }

  public func results(
    for languages: [LanguageRecord], font config: FontConfiguration, priority: [String] = [],
    progress: @Sendable ([String: LanguageCoverage]) async -> Void = { _ in }
  ) async throws -> [String: LanguageCoverage] {
    try Task.checkCancellation()
    let key = Self.key(config)
    touch(key)
    let available = FontRenderer.isAvailable(key)
    let font = FontRenderer.font(key)
    let charset = CTFontCopyCharacterSet(font)
    let configuredName = CTFontCopyPostScriptName(font) as String
    let priorities = Dictionary(
      priority.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
    let ordered = languages.enumerated().sorted {
      let lhs = priorities[$0.element.id] ?? Int.max
      let rhs = priorities[$1.element.id] ?? Int.max
      return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
    }.map(\.element)
    var results: [String: LanguageCoverage] = [:]
    for language in ordered {
      try Task.checkCancellation()
      touch(key)
      var cached = cache[key]!
      if let ready = cached.languages[language.id] {
        results[language.id] = ready
      } else {
        var orthographies: [String: OrthographyCoverage] = [:]
        for orthography in language.orthographies {
          var categories: [LanguageCategory: InventoryCoverage] = [:]
          for category in LanguageCategory.allCases {
            let requirements = orthography[category].probes
            var missing: [LanguageRequirement] = []
            for requirement in requirements {
              try Task.checkCancellation()
              let supported: Bool
              if let ready = cached.probes[requirement] {
                supported = ready
              } else {
                supported =
                  available
                  && (requirement.sequence
                    ? FontRenderer.supports(
                      FontRenderer.line(
                        requirement.text, config: key, font: font, size: key.size, tracking: false),
                      configuredName: configuredName)
                    : requirement.scalars.allSatisfy {
                      CFCharacterSetIsLongCharacterMember(charset, $0.value)
                    })
                cached.probes[requirement] = supported
              }
              if !supported { missing.append(requirement) }
            }
            categories[category] = InventoryCoverage(required: requirements.count, missing: missing)
          }
          orthographies[orthography.id] = OrthographyCoverage(categories: categories)
        }
        let coverage = LanguageCoverage(available: available, orthographies: orthographies)
        cached.languages[language.id] = coverage
        results[language.id] = coverage
        cache[key] = cached
      }
      if results.count == 1 || results.count.isMultiple(of: 16) || results.count == ordered.count {
        await progress(results)
      }
    }
    return results
  }
}
