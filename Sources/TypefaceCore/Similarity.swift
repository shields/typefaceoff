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

import Foundation

/// Versioned input shared by catalog discovery, fitting, and reproducible benchmarks.
public struct SimilarityCorpus: Hashable, Sendable {
  public static let version = 1
  public let glyphs: [String]
  public let runs: [String]
  public let requiredText: String

  public init(glyphs: [String], runs: [String], requiredText: String = "") {
    self.glyphs = Array(Set(glyphs.filter { !$0.isEmpty })).sorted()
    self.runs = Array(Set(runs.filter { !$0.isEmpty })).sorted()
    self.requiredText = requiredText
  }

  public static let diagnostic = SimilarityCorpus(
    glyphs: [" "] + Differences.candidates(sample: "ÁÅÉáéöñ"),
    runs: [
      "Hamburg", "minimum", "ag Il 0", "AV To", "fi fl", "ff ffi ffl", "st ct",
      "1/2", "1820", ".:", "!?", "(A)", "ABC", "r ->", "1st", "a a", "a  a",
    ])

  // Diagnostic glyphs/runs only supplement the required text, so unlike
  // `requiredText` coverage, a candidate is free to lack one: excluding it here
  // (rather than letting the engine throw mid-search) keeps fitting usable for
  // any font that fully supports the user's actual comparison text.
  public static func fitting(
    reference: FontConfiguration, candidate: FontConfiguration, text: String
  )
    -> Self
  {
    let words = Array(Set(text.split(whereSeparator: \.isWhitespace).map(String.init))).sorted()
    let selected = sampled(words, limit: 128)
    func supported(_ text: String) -> Bool {
      FontRenderer.supports(text, config: reference, size: reference.size)
        && FontRenderer.supports(text, config: candidate, size: candidate.size)
    }
    return SimilarityCorpus(
      glyphs: Array(Set(text.map(String.init))) + diagnostic.glyphs.filter(supported),
      runs: selected + diagnostic.runs.filter(supported),
      requiredText: text)
  }

  public var screening: Self {
    Self(glyphs: Self.sampled(glyphs, limit: 16), runs: Self.sampled(runs, limit: 8))
  }

  static func sampled(_ values: [String], limit: Int) -> [String] {
    guard values.count > limit else { return values }
    return (0..<limit).map { values[$0 * (values.count - 1) / (limit - 1)] }
  }
}

public struct SimilarityScore: Codable, Equatable, Sendable {
  public static let version = 1
  static let improvementTolerance = 1e-6
  public let geometry: Double
  public let appearance: Double
  public let shapedText: Double
  public let metrics: Double
  public var total: Double { (geometry + appearance + shapedText + metrics) / 4 }

  public init(geometry: Double, appearance: Double, shapedText: Double, metrics: Double) {
    self.geometry = geometry
    self.appearance = appearance
    self.shapedText = shapedText
    self.metrics = metrics
  }
}

public enum SimilarityError: Error, Equatable, Sendable, LocalizedError {
  case unavailableFont(String)
  case unsupportedText(String, String)
  case invalidConfiguration
  case emptyCorpus
  case renderingFailed

  public var errorDescription: String? {
    switch self {
    case .unavailableFont(let name): "Font unavailable: \(name)"
    case .unsupportedText(let name, let text):
      "\(name) cannot render \(String(text.prefix(24))) without a fallback font."
    case .invalidConfiguration: "The font settings or rendering scale are invalid."
    case .emptyCorpus: "No characters are available to compare."
    case .renderingFailed: "The comparison sample could not be rendered."
    }
  }
}

public struct FamilySimilarity: Identifiable, Sendable {
  public var id: String { family }
  public let family: String
  public let score: SimilarityScore?
  public let unavailableReason: String?

  public init(family: String, score: SimilarityScore?, unavailableReason: String? = nil) {
    self.family = family
    self.score = score
    self.unavailableReason = unavailableReason
  }
}

extension FontCatalog {
  public func defaultConfiguration(in family: String, size: Double) -> FontConfiguration? {
    guard let face = preferredFace(in: family), namesByFamily[family]?.contains(face.id) == true,
      FontRenderer.isAvailable(FontConfiguration(face.id))
    else { return nil }
    var config = FontConfiguration(face.id)
    config.size = size
    config.matchOpticalSize(face.axes)
    return config
  }
}

extension FontConfiguration {
  /// Face coordinates come from a 22-point font, so their optical size is 22; Core Text's
  /// automatic optical size follows the actual point size.
  mutating func matchOpticalSize(_ axes: [FontAxis]) {
    if let axis = axes.first(where: { $0.tag == "opsz" }) {
      self.axes[axis.id] = size.clamped(to: axis.minimum...axis.maximum)
    }
  }
}
