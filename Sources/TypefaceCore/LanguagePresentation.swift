import Foundation

public enum LanguageColumn: String, CaseIterable, Sendable {
  case language = "Language"
  case speakers = "Speakers"
  case a = "A"
  case b = "B"
}

public struct LanguageOrdering: Equatable, Sendable {
  public var column: LanguageColumn = .speakers
  public var ascending = false

  public init() {}

  public mutating func select(_ column: LanguageColumn) {
    ascending = self.column == column ? !ascending : column == .language
    self.column = column
  }

  public func sorted(
    _ languages: [LanguageRecord], a: [String: LanguageCoverage], b: [String: LanguageCoverage]
  ) -> [LanguageRecord] {
    languages.sorted { lhs, rhs in
      let name = lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive])
      let comparison: ComparisonResult
      switch column {
      case .language: comparison = name
      case .speakers: comparison = Self.compare(lhs.speakers ?? -1, rhs.speakers ?? -1)
      case .a, .b:
        let coverage = column == .a ? a : b
        comparison = Self.compare(
          LanguageCoverageMark(coverage[lhs.id], language: lhs).rawValue,
          LanguageCoverageMark(coverage[rhs.id], language: rhs).rawValue)
      }
      if comparison == .orderedSame {
        return name == .orderedSame ? lhs.id < rhs.id : name == .orderedAscending
      }
      return comparison == (ascending ? .orderedAscending : .orderedDescending)
    }
  }

  private static func compare(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
    lhs == rhs ? .orderedSame : lhs < rhs ? .orderedAscending : .orderedDescending
  }
}

public enum LanguageCoverageMark: Int, Sendable {
  case checking, unavailable, incomplete, complete

  public init(_ coverage: LanguageCoverage?, language: LanguageRecord) {
    guard let coverage else {
      self = .checking
      return
    }
    self =
      !coverage.available ? .unavailable : coverage.complete(language) ? .complete : .incomplete
  }

  public var title: String {
    switch self {
    case .checking: "Checking"
    case .unavailable: "Font unavailable"
    case .incomplete: "Incomplete"
    case .complete: "Complete"
    }
  }
}

public enum LanguagePresentation {
  public static func cells(_ inventory: LanguageInventory) -> [String] {
    inventory.tokens.flatMap { $0.map(String.init) }
  }

  public static func speakers(_ count: Int?) -> String {
    guard let count else { return "—" }
    let divisor = count >= 1_000_000 ? 1_000_000 : count >= 1_000 ? 1_000 : 1
    let suffix = divisor == 1_000_000 ? "M" : divisor == 1_000 ? "k" : ""
    return String(Int((Double(count) / Double(divisor)).rounded())) + suffix
  }

  public static func facts(_ language: LanguageRecord) -> String {
    let autonyms = language.autonyms.filter {
      !$0.isEmpty && $0.compare(language.name, options: [.caseInsensitive]) != .orderedSame
    }
    let count = language.speakers.map { "\($0.formatted()) speakers" } ?? "Speaker count unknown"
    let date = language.speakersDate.map { " (\($0))" } ?? ""
    return
      ([language.id] + autonyms + [count + date, "\(language.validity) data"]
      + (language.historical ? ["Historical"] : [])).joined(separator: " · ")
  }

  public static func script(_ orthography: OrthographyRecord) -> String {
    "\(orthography.script) (\(orthography.scriptCode))"
      + (orthography.historical ? " · Historical" : "")
      + (orthography.grouped ? " · Required group" : "")
  }
}
