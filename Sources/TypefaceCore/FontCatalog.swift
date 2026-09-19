import CoreText
import Foundation
import Synchronization

public struct FontAxis: Identifiable, Hashable, Sendable {
  public let id: UInt32
  public let name: String
  public let minimum: Double
  public let maximum: Double
  public let defaultValue: Double
  public var tag: String { fontTag(id) }
}

public struct FontFeature: Identifiable, Hashable, Sendable {
  public enum Group: String, CaseIterable, Sendable {
    case common = "Common"
    case characterVariants = "Character variants"
    case stylisticSets = "Stylistic sets"
    case numbers = "Numbers"
    case automatic = "Automatic shaping"
  }

  static let automaticTags: Set<String> = [
    "ccmp", "locl", "rlig", "mark", "mkmk", "init", "medi", "fina", "isol",
  ]

  public struct Option: Hashable, Sendable {
    public let name: String
    public let value: Int
  }
  public let id: String
  public let name: String
  public let options: [Option]
  public let defaultValue: Int
  public var sample: String? = nil

  public var isAutomatic: Bool {
    id.hasPrefix("ot.") && Self.automaticTags.contains(String(id.dropFirst(3)))
  }

  public var group: Group {
    if isAutomatic { return .automatic }
    if id.hasPrefix("ot.") {
      let tag = String(id.dropFirst(3))
      if tag.hasPrefix("cv") || ["aalt", "salt"].contains(tag) { return .characterVariants }
      if tag.hasPrefix("ss") { return .stylisticSets }
      if [
        "tnum", "pnum", "lnum", "onum", "ordn", "sups", "subs", "sinf", "numr", "dnom", "frac",
        "zero",
      ].contains(tag) {
        return .numbers
      }
    } else if let type = id.split(separator: ".").dropFirst().first.flatMap({ Int($0) }) {
      switch type {
      case kNumberSpacingType, kVerticalPositionType, kFractionsType, kNumberCaseType:
        return .numbers
      case kCharacterAlternativesType, kCharacterShapeType: return .characterVariants
      case kStylisticAlternativesType: return .stylisticSets
      default: break
      }
    }
    return .common
  }
}

public struct FontFace: Identifiable, Hashable, Sendable {
  private static let cache = Mutex<[String: FontFace]>([:])
  public static func named(_ name: String) -> FontFace {
    if let cached = cache.withLock({ $0[name] }) { return cached }
    let face = FontFace(postScriptName: name)
    cache.withLock { $0[name] = face }
    return face
  }
  public let id: String
  public let family: String
  public let style: String
  public let weight: Double
  public let italic: Bool
  public let axes: [FontAxis]
  public let coordinates: [UInt32: Double]
  public let features: [FontFeature]
  public let unitsPerEm: Int

  public init(postScriptName: String) {
    let font = CTFontCreateWithName(postScriptName as CFString, 22, nil)
    id = CTFontCopyPostScriptName(font) as String
    family = CTFontCopyFamilyName(font) as String
    italic = CTFontGetSymbolicTraits(font).contains(.traitItalic)
    unitsPerEm = Int(CTFontGetUnitsPerEm(font))
    let attributes = Self.readAttributes(
      styleName: CTFontCopyName(font, kCTFontStyleNameKey) as String?,
      variation: CTFontCopyVariation(font) as? [NSNumber: NSNumber],
      axes: CTFontCopyVariationAxes(font) as? [[String: Any]],
      os2: CTFontCopyTable(font, tagNumber("OS/2"), []) as Data?)
    style = attributes.style
    coordinates = attributes.coordinates
    axes = attributes.axes
    weight = attributes.weight
    features = Self.readFeatures(
      tables: Dictionary(
        uniqueKeysWithValues: ["GSUB", "GPOS"].compactMap { tag in
          (CTFontCopyTable(font, tagNumber(tag), []) as Data?).map { (tag, $0) }
        }),
      names: Self.readNames(CTFontCopyTable(font, tagNumber("name"), []) as Data?),
      aat: (CTFontCopyFeatures(font) as? [[String: Any]]) ?? [])
  }

  /// Interpret optional Core Text metadata independently of installed fonts.
  static func readAttributes(
    styleName: String?, variation: [NSNumber: NSNumber]?, axes rawAxes: [[String: Any]]?, os2: Data?
  ) -> (style: String, coordinates: [UInt32: Double], axes: [FontAxis], weight: Double) {
    let coordinates = Dictionary(
      uniqueKeysWithValues: (variation ?? [:]).map {
        ($0.key.uint32Value, $0.value.doubleValue)
      })
    let axes = (rawAxes ?? []).compactMap { axis -> FontAxis? in
      guard let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,
        let minimum = axis[kCTFontVariationAxisMinimumValueKey as String] as? Double,
        let maximum = axis[kCTFontVariationAxisMaximumValueKey as String] as? Double,
        let value = axis[kCTFontVariationAxisDefaultValueKey as String] as? Double
      else { return nil }
      return FontAxis(
        id: identifier.uint32Value,
        name: axis[kCTFontVariationAxisNameKey as String] as? String
          ?? fontTag(identifier.uint32Value),
        minimum: minimum, maximum: maximum, defaultValue: value)
    }.sorted { ($0.tag == "wght" ? 0 : 1, $0.name) < ($1.tag == "wght" ? 0 : 1, $1.name) }
    // OS/2 weights use the same 1–1000 scale as the OpenType wght axis.
    let weight = coordinates[tagNumber("wght")] ?? Double(os2.flatMap { readUInt16($0, 4) } ?? 400)
    return (styleName ?? "Regular", coordinates, axes, weight)
  }

  static func readFeatures(tables: [String: Data], names: [UInt16: String], aat: [[String: Any]])
    -> [FontFeature]
  {
    var tags = Set<String>()
    var labels: [String: String] = [:]
    var alternatives: [String: [FontFeature.Option]] = [:]
    var samples: [String: String] = [:]
    for table in ["GSUB", "GPOS"] {
      guard let data = tables[table],
        let offset = readUInt16(data, 6), let count = readUInt16(data, Int(offset))
      else { continue }
      for index in 0..<Int(count) {
        let start = Int(offset) + 2 + index * 6
        guard start + 4 <= data.count else { break }
        let tag = String(decoding: data[start..<start + 4], as: UTF8.self)
        tags.insert(tag)
        guard tag.hasPrefix("cv") || tag.hasPrefix("ss"),
          let relative = readUInt16(data, start + 4),
          let parameters = readUInt16(data, Int(offset) + Int(relative)), parameters != 0
        else { continue }
        let parameterStart = Int(offset) + Int(relative) + Int(parameters)
        if let nameID = readUInt16(data, parameterStart + 2), let label = names[nameID] {
          labels[tag] = label
        }
        if tag.hasPrefix("cv") {
          if let count = readUInt16(data, parameterStart + 8),
            let first = readUInt16(data, parameterStart + 10), count > 0
          {
            alternatives[tag] = (0..<Int(count)).map { index in
              .init(
                name: UInt16(exactly: Int(first) + index).flatMap { names[$0] }
                  ?? "Alternate \(index + 1)", value: index + 1)
            }
          }
          if let count = readUInt16(data, parameterStart + 12) {
            samples[tag] = (0..<min(8, Int(count))).compactMap { index -> String? in
              let position = parameterStart + 14 + index * 3
              guard position + 3 <= data.count else { return nil }
              let value =
                UInt32(data[position]) << 16 | UInt32(data[position + 1]) << 8
                | UInt32(data[position + 2])
              return UnicodeScalar(value).map(String.init)
            }.joined()
          }
        }
      }
    }
    var result = tags.sorted().map { tag in
      FontFeature(
        id: "ot.\(tag)", name: labels[tag] ?? featureName(tag),
        options: FontFeature.automaticTags.contains(tag)
          ? []
          : [.init(name: "Off", value: 0)]
            + (alternatives[tag] ?? [.init(name: "On", value: 1)]),
        defaultValue: FontFeature.automaticTags.contains(tag)
          || ["kern", "liga", "clig", "calt"].contains(tag) ? 1 : 0,
        sample: samples[tag]?.isEmpty == false ? samples[tag] : nil)
    }
    // AAT-only fonts (including Helvetica Neue) expose selectors through Core Text.
    if tags.isEmpty {
      for group in aat {
        guard let type = group[kCTFontFeatureTypeIdentifierKey as String] as? Int,
          let name = group[kCTFontFeatureTypeNameKey as String] as? String,
          let selectors = group[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]]
        else { continue }
        let options = selectors.compactMap { item -> FontFeature.Option? in
          guard let value = item[kCTFontFeatureSelectorIdentifierKey as String] as? Int,
            let label = item[kCTFontFeatureSelectorNameKey as String] as? String
          else { return nil }
          return .init(name: label, value: value)
        }
        let defaults = selectors.filter {
          ($0[kCTFontFeatureSelectorDefaultKey as String] as? Bool) == true
        }
        .compactMap { $0[kCTFontFeatureSelectorIdentifierKey as String] as? Int }
        if group[kCTFontFeatureTypeExclusiveKey as String] as? Bool == true {
          result.append(
            .init(
              id: "aat.\(type)", name: name, options: options, defaultValue: defaults.first ?? 0))
        } else {
          for option in options where option.value.isMultiple(of: 2) {
            result.append(
              .init(
                id: "aat.\(type).\(option.value)", name: option.name,
                options: [
                  .init(name: "Off", value: option.value + 1),
                  .init(name: "On", value: option.value),
                ],
                defaultValue: defaults.contains(option.value) ? option.value : option.value + 1))
          }
        }
      }
    }
    // Kerning is also controlled as a shaping attribute, for fonts with legacy kern tables.
    if !result.contains(where: { $0.id == "ot.kern" }) {
      result.insert(
        .init(
          id: "ot.kern", name: "Kerning",
          options: [.init(name: "Off", value: 0), .init(name: "On", value: 1)], defaultValue: 1),
        at: 0)
    }
    return result
  }

  static func readNames(_ data: Data?) -> [UInt16: String] {
    guard let data,
      let count = readUInt16(data, 2), let storage = readUInt16(data, 4)
    else { return [:] }
    var result: [UInt16: String] = [:]
    var priorities: [UInt16: Int] = [:]
    for index in 0..<Int(count) {
      let position = 6 + 12 * index
      guard let platform = readUInt16(data, position), [0, 1, 3].contains(platform),
        let language = readUInt16(data, position + 4), let id = readUInt16(data, position + 6),
        let length = readUInt16(data, position + 8), let offset = readUInt16(data, position + 10)
      else { continue }
      let start = Int(storage) + Int(offset)
      let end = start + Int(length)
      guard end <= data.count, platform == 1 || length.isMultiple(of: 2),
        let value = String(
          data: data[start..<end], encoding: platform == 1 ? .macOSRoman : .utf16BigEndian)
      else { continue }
      let priority = ([0, 0x409].contains(language) ? 10 : 0) + (platform == 1 ? 0 : 2)
      if priority > priorities[id, default: -1] {
        result[id] = value
        priorities[id] = priority
      }
    }
    return result
  }
}

public struct FontCatalog: Sendable {
  public let families: [String]
  public let namesByFamily: [String: [String]]

  public init() {
    self.init(
      descriptors:
        CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionCreateFromAvailableFonts(nil))
        as? [CTFontDescriptor])
  }

  init(descriptors: [CTFontDescriptor]?) {
    var names: [String: Set<String>] = [:]
    for descriptor in descriptors ?? [] {
      guard
        let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute)
          as? String,
        let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
        !family.hasPrefix(".")
      else { continue }
      names[family, default: []].insert(name)
    }
    families = names.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    namesByFamily = names.mapValues { $0.sorted() }
  }

  public func faces(in family: String) -> [FontFace] {
    (namesByFamily[family] ?? []).map { FontFace.named($0) }.sorted {
      if $0.italic != $1.italic { return !$0.italic }
      if $0.weight != $1.weight { return $0.weight < $1.weight }
      return $0.style < $1.style
    }
  }

  public func preferredFace(in family: String, italic: Bool = false) -> FontFace? {
    let all = faces(in: family)
    let matching = all.filter { $0.italic == italic }
    let options = matching.isEmpty ? all : matching
    return options.first {
      !$0.axes.isEmpty && $0.style.localizedCaseInsensitiveContains("regular")
    }
      ?? options.first { !$0.axes.isEmpty }
      ?? options.min {
        abs($0.weight - 400) < abs($1.weight - 400)
      }
  }
}

public func tagNumber(_ text: String) -> UInt32 {
  text.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
}

public func fontTag(_ number: UInt32) -> String {
  String(decoding: [24, 16, 8, 0].map { UInt8((number >> $0) & 255) }, as: UTF8.self)
}

private func readUInt16(_ data: Data, _ offset: Int) -> UInt16? {
  guard offset >= 0, offset + 2 <= data.count else { return nil }
  return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
}

private func featureName(_ tag: String) -> String {
  let names = [
    "kern": "Kerning", "liga": "Standard ligatures", "clig": "Contextual ligatures",
    "dlig": "Discretionary ligatures", "calt": "Contextual alternates",
    "case": "Case-sensitive forms", "cpsp": "Capital spacing", "frac": "Fractions",
    "zero": "Slashed zero", "tnum": "Tabular numerals", "pnum": "Proportional numerals",
    "lnum": "Lining numerals", "onum": "Oldstyle numerals", "ordn": "Ordinals",
    "sups": "Superscript", "subs": "Subscript", "salt": "Stylistic alternates",
    "aalt": "Alternate forms",
    "sinf": "Scientific inferiors", "numr": "Numerators", "dnom": "Denominators",
    "ccmp": "Glyph composition", "locl": "Localized forms", "rlig": "Required ligatures",
    "mark": "Mark positioning", "mkmk": "Mark-to-mark positioning", "init": "Initial forms",
    "medi": "Medial forms", "fina": "Final forms", "isol": "Isolated forms",
  ]
  if let name = names[tag] { return name }
  if tag.hasPrefix("cv") { return "Character variant \(Int(tag.dropFirst(2)) ?? 0)" }
  if tag.hasPrefix("ss") { return "Stylistic set \(Int(tag.dropFirst(2)) ?? 0)" }
  return tag
}
