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

import CoreText
import Foundation
import Testing

@testable import TypefaceCore

@Suite struct FontMetadataTests {
  @Test(arguments: [
    ["wdth", "wght", "opsz"], ["wght", "opsz", "wdth"], ["opsz", "wdth", "wght"],
  ])
  func weightAxesPrecedeOtherAxesSortedByName(order: [String]) {
    let names = ["wght": "Z weight", "wdth": "Width", "opsz": "Optical size"]
    let axes: [[String: Any]] = order.map { tag in
      [
        kCTFontVariationAxisIdentifierKey as String: NSNumber(value: tagNumber(tag)),
        kCTFontVariationAxisNameKey as String: names[tag]!,
        kCTFontVariationAxisMinimumValueKey as String: 0.0,
        kCTFontVariationAxisMaximumValueKey as String: 1000.0,
        kCTFontVariationAxisDefaultValueKey as String: 100.0,
      ]
    }
    let parsed = FontFace.readAttributes(styleName: nil, variation: nil, axes: axes, os2: nil)
    #expect(parsed.axes.map(\.tag) == ["wght", "opsz", "wdth"])
    #expect(parsed.axes.map(\.name) == ["Z weight", "Optical size", "Width"])
  }

  @Test func absentOrMalformedFontAttributesUseDocumentedDefaults() {
    let empty = FontFace.readAttributes(styleName: nil, variation: nil, axes: nil, os2: nil)
    #expect(empty.style == "Regular")
    #expect(empty.weight == 400 && empty.width == 1)
    #expect(empty.axes.isEmpty && empty.coordinates.isEmpty)
    let width: [String: Any] = [
      kCTFontVariationAxisIdentifierKey as String: NSNumber(value: tagNumber("wdth")),
      kCTFontVariationAxisMinimumValueKey as String: 0.5,
      kCTFontVariationAxisMaximumValueKey as String: 2.0,
      kCTFontVariationAxisDefaultValueKey as String: 1.0,
    ]
    var inverted = width
    inverted[kCTFontVariationAxisMinimumValueKey as String] = 3.0
    let parsed = FontFace.readAttributes(
      styleName: "Italic", variation: nil, axes: [[:], inverted, width], os2: words([0, 0, 650]))
    #expect(parsed.style == "Italic" && parsed.weight == 650 && parsed.width == 1)
    #expect(parsed.axes.map(\.name) == ["wdth"])
    #expect(parsed.axes.first?.minimum == 0.5 && parsed.axes.first?.maximum == 2)
    let truncated = FontFace.readAttributes(
      styleName: nil, variation: nil, axes: nil, os2: Data([0]))
    #expect(truncated.weight == 400 && truncated.width == 1)
    for (widthClass, width) in [(3, 0.75), (9, 2.0), (0, 1.0), (10, 1.0)] {
      let os2 = words([0, 0, 400, UInt16(widthClass)])
      #expect(
        FontFace.readAttributes(styleName: nil, variation: nil, axes: nil, os2: os2).width == width)
    }
    let condensed = FontFace.readAttributes(
      styleName: nil, variation: [NSNumber(value: tagNumber("wdth")): 0.8], axes: [width],
      os2: words([0, 0, 400, 9]))
    #expect(condensed.width == 0.8)
  }

  @Test func catalogHandlesEmptyAndIncompleteFontCollections() {
    let empty = FontCatalog(descriptors: nil)
    #expect(empty.families.isEmpty && empty.namesByFamily.isEmpty)
    #expect(empty.faces(in: "Missing").isEmpty)
    #expect(empty.preferredFace(in: "Missing") == nil)
    let invalid = CTFontDescriptorCreateWithAttributes([:] as CFDictionary)
    let hidden = CTFontDescriptorCreateWithAttributes(
      [
        kCTFontFamilyNameAttribute: ".Hidden", kCTFontNameAttribute: "Hidden-Regular",
      ] as CFDictionary)
    #expect(FontCatalog(descriptors: [hidden]).families.isEmpty)
    #expect(
      FontCatalog(descriptors: [invalid]).families.allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") })
  }
  @Test func characterVariantParametersExposeLabelsAlternatesAndUnicodeSamples() throws {
    let parameters = words([0, 256, 0, 0, 2, 257, 3]) + Data([0, 0, 97, 1, 246, 0, 17, 0, 0])
    let table = featureTable("cv01", parameters: parameters)
    let features = FontFace.readFeatures(
      tables: ["GSUB": table], names: [256: "Alternate a", 257: "Round form"], aat: [])
    let variant = try #require(features.first { $0.id == "ot.cv01" })
    #expect(variant.name == "Alternate a")
    #expect(variant.options.map(\.name) == ["Off", "Round form", "Alternate 2"])
    #expect(variant.options.map(\.value) == [0, 1, 2])
    #expect(variant.sample == "a😀")
    #expect(features.first?.id == "ot.kern")
    for length in 0..<table.count {
      let truncated = FontFace.readFeatures(
        tables: ["GSUB": table.prefix(length)], names: [:], aat: [])
      #expect(truncated.first?.id == "ot.kern")
      #expect(truncated.allSatisfy { $0.id == "ot.kern" || $0.id == "ot.cv01" })
    }
  }

  @Test func missingParameterNamesAndInvalidSamplesHaveSafeDefaults() throws {
    for (tag, name) in [
      ("cvxx", "Character variant 0"), ("ssxx", "Stylistic set 0"), ("zzzz", "zzzz"),
    ] {
      let features = FontFace.readFeatures(
        tables: ["GPOS": featureTable(tag, parameters: words([0, 256, 0, 0, 2, 65535, 0]))],
        names: [:], aat: [])
      let feature = try #require(features.first { $0.id == "ot.\(tag)" })
      #expect(feature.name == name)
      #expect(feature.sample == nil)
      #expect(feature.defaultValue == 0)
      if tag.hasPrefix("cv") {
        #expect(feature.options.map(\.name) == ["Off", "Alternate 1", "Alternate 2"])
      }
    }
  }

  @Test func aatSelectorsPreserveExclusivityAndDefaultStates() throws {
    let selector: (Int, String, Bool) -> [String: Any] = { value, name, isDefault in
      [
        kCTFontFeatureSelectorIdentifierKey as String: value,
        kCTFontFeatureSelectorNameKey as String: name,
        kCTFontFeatureSelectorDefaultKey as String: isDefault,
      ]
    }
    let group: (Int, Bool, [[String: Any]]) -> [String: Any] = { type, exclusive, selectors in
      [
        kCTFontFeatureTypeIdentifierKey as String: type,
        kCTFontFeatureTypeNameKey as String: "Feature \(type)",
        kCTFontFeatureTypeExclusiveKey as String: exclusive,
        kCTFontFeatureTypeSelectorsKey as String: selectors,
      ]
    }
    let features = FontFace.readFeatures(
      tables: [:], names: [:],
      aat: [
        [:],
        group(6, true, [selector(0, "Tabular", false), selector(1, "Proportional", false), [:]]),
        group(
          1, false,
          [
            selector(2, "Common", true), selector(3, "Disable common", false),
            selector(4, "Rare", false), selector(5, "Disable rare", true),
          ]),
      ])
    let numberSpacing = try #require(features.first { $0.id == "aat.6" })
    #expect(numberSpacing.options.map(\.name) == ["Tabular", "Proportional"])
    #expect(numberSpacing.defaultValue == 0)
    #expect(features.first { $0.id == "aat.1.2" }?.defaultValue == 2)
    #expect(features.first { $0.id == "aat.1.4" }?.defaultValue == 5)
    #expect(features.first { $0.id == "aat.1.4" }?.options.map(\.value) == [5, 4])
  }

  @Test func nameRecordsPreferEnglishUnicodeAndRejectTruncatedStorage() throws {
    let records: [(UInt16, UInt16, UInt16, String)] = [
      (1, 0, 256, "Mac name"), (3, 0x409, 256, "Unicode name"),
      (3, 0x411, 256, "Lower priority"), (0, 0, 257, "Alternate"),
      (2, 0, 258, "Unsupported"),
    ]
    var headers = Data()
    var storage = Data()
    for (platform, language, id, text) in records {
      let data = try #require(text.data(using: platform == 1 ? .macOSRoman : .utf16BigEndian))
      headers += words([platform, 0, language, id, UInt16(data.count), UInt16(storage.count)])
      storage += data
    }
    let table = words([0, UInt16(records.count), UInt16(6 + headers.count)]) + headers + storage
    #expect(FontFace.readNames(table) == [256: "Unicode name", 257: "Alternate"])
    #expect(FontFace.readNames(nil).isEmpty)
    for length in 0..<table.count {
      let names = FontFace.readNames(table.prefix(length))
      #expect(Set(names.keys).isSubset(of: [256, 257]))
    }
    let invalidUTF16 = words([0, 1, 18, 3, 0, 0x409, 256, 1, 0]) + Data([0])
    #expect(FontFace.readNames(invalidUTF16).isEmpty)
  }

  private func words(_ values: [UInt16]) -> Data {
    Data(values.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] })
  }

  private func featureTable(_ tag: String, parameters: Data) -> Data {
    words([1, 0, 0, 10, 0, 1]) + Data(tag.utf8) + words([8, 4, 0]) + parameters
  }
}

extension FontMetadataTests {
  @Test func requiredLanguageFeaturesRemainAutomaticEvenForPrivateTags() throws {
    func words(_ values: [UInt16]) -> Data {
      Data(values.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] })
    }
    // Header, ScriptList, Script with default and named LangSys, then FeatureList.
    let header = words([1, 0, 10, 42, 0])
    let scripts = words([1]) + Data("latn".utf8) + words([8])
    let script = words([10, 1]) + Data("ENG ".utf8) + words([16])
    let languages = words([0, 0, 0, 0, 1, 0])
    let features =
      words([2]) + Data("priv".utf8) + words([14]) + Data("xxxx".utf8) + words([18])
      + words([0, 0, 0, 0])
    let table = header + scripts + script + languages + words([0]) + features
    #expect(FontFace.requiredFeatureIndices(table) == [0, 1])
    let parsed = FontFace.readFeatures(tables: ["GSUB": table], names: [:], aat: [])
    let required = try #require(parsed.first { $0.id == "ot.priv" })
    #expect(required.required && required.isAutomatic && required.options.isEmpty)
    #expect(required.defaultValue == 1 && required.group == .automatic)
    for length in 0..<table.count { _ = FontFace.requiredFeatureIndices(table.prefix(length)) }
    var noDefault = table
    noDefault.replaceSubrange(18..<20, with: words([0]))
    noDefault.replaceSubrange(36..<38, with: words([0xFFFF]))
    #expect(FontFace.requiredFeatureIndices(noDefault).isEmpty)
    #expect(
      FontFeature(id: "aat.1.0", name: "Required ligatures", options: [], defaultValue: 0)
        .isAutomatic)
  }
}
