import Foundation

// Generates Sources/TypefaceCore/Resources/character-frequencies.tsv: a
// global, speaker-weighted table of per-character shares, built from FineFreq
// (per-language web-text character frequencies) and the Leipzig Corpora
// Collection (used to estimate the compatibility characters FineFreq's NFKC
// normalization discards). Run via `make frequencies`; see that target for
// how this file is compiled and executed.

// MARK: - Pinned inputs

/// FineFreq (Xu 2025, arXiv:2512.09701, CC BY 4.0): https://github.com/Bin-2/FineFreq
let fineFreqCommit = "79a6bd84a7a188ebf95d66fb4b20e344d4937e3a"
let fineFreqRawBase = "https://raw.githubusercontent.com/Bin-2/FineFreq/\(fineFreqCommit)"
let leipzigDownloadBase = "https://downloads.wortschatz-leipzig.de/corpora"

let cacheRoot = URL(fileURLWithPath: ".build/character-frequencies")
let fineFreqCacheDir = cacheRoot.appendingPathComponent("finefreq")
let leipzigCacheDir = cacheRoot.appendingPathComponent("leipzig")
let outputPath = "Sources/TypefaceCore/Resources/character-frequencies.tsv"

/// A code's share of the global mix must reach this to appear in the output.
let truncationFloor = 1e-5

/// Speakers: Ethnologue, Languages of the World, 29th edition (2026), SIL
/// Global, as reproduced in Wikipedia's "List of languages by total number of
/// speakers" (revision 1342700363). Of the top 40, Hausa, Sudanese Arabic,
/// Jinyu, and Min Nan have no FineFreq table. Greek, Hebrew, and Polish, which
/// rank below the top 40, are added so that their common letters aren't left
/// at the floor; their speakers are Ethnologue's 22nd edition (2019) figures as
/// recorded in Wikidata, first-language only for Greek and Polish.
/// `manifestISO` is FineFreq's code, which differs from Ethnologue's for Iranian
/// Persian (pes → fas) and Tagalog (tgl → fil).
struct Language {
  let name: String
  let manifestISO: String
  let speakers: Int
  let leipzigCorpusID: String
  let leipzigCorpusBytes: Int
}

let languages: [Language] = [
  Language(
    name: "English", manifestISO: "eng", speakers: 1_493_000_000,
    leipzigCorpusID: "eng-com_web-public_2018_100K", leipzigCorpusBytes: 23_144_388),
  Language(
    name: "Mandarin Chinese", manifestISO: "cmn", speakers: 1_183_000_000,
    leipzigCorpusID: "zho-cn_web_2015_100K", leipzigCorpusBytes: 41_967_803),
  Language(
    name: "Hindi", manifestISO: "hin", speakers: 611_200_000,
    leipzigCorpusID: "hin_mixed_2019_100K", leipzigCorpusBytes: 23_434_441),
  Language(
    name: "Spanish", manifestISO: "spa", speakers: 561_300_000,
    leipzigCorpusID: "spa_web_2016_100K", leipzigCorpusBytes: 18_445_761),
  Language(
    name: "Standard Arabic", manifestISO: "arb", speakers: 334_900_000,
    leipzigCorpusID: "ara_web_2011_100K", leipzigCorpusBytes: 21_754_924),
  Language(
    name: "French", manifestISO: "fra", speakers: 333_500_000,
    leipzigCorpusID: "fra_mixed_2009_100K", leipzigCorpusBytes: 25_694_033),
  Language(
    name: "Bengali", manifestISO: "ben", speakers: 274_400_000,
    leipzigCorpusID: "ben-bd_web_2017_100K", leipzigCorpusBytes: 19_495_946),
  Language(
    name: "Portuguese", manifestISO: "por", speakers: 269_400_000,
    leipzigCorpusID: "por_news_2023_100K", leipzigCorpusBytes: 27_565_200),
  Language(
    name: "Indonesian", manifestISO: "ind", speakers: 254_800_000,
    leipzigCorpusID: "ind_web_2012_100K", leipzigCorpusBytes: 20_275_741),
  Language(
    name: "Urdu", manifestISO: "urd", speakers: 246_000_000,
    leipzigCorpusID: "urd_newscrawl_2016_100K", leipzigCorpusBytes: 30_085_044),
  Language(
    name: "Russian", manifestISO: "rus", speakers: 210_300_000,
    leipzigCorpusID: "rus-ru_web-public_2019_100K", leipzigCorpusBytes: 20_416_237),
  Language(
    name: "Standard German", manifestISO: "deu", speakers: 133_400_000,
    leipzigCorpusID: "deu-de_web_2021_100K", leipzigCorpusBytes: 20_312_560),
  Language(
    name: "Japanese", manifestISO: "jpn", speakers: 125_700_000,
    leipzigCorpusID: "jpn-jp_web_2020_100K", leipzigCorpusBytes: 27_138_842),
  Language(
    name: "Nigerian Pidgin", manifestISO: "pcm", speakers: 120_700_000,
    leipzigCorpusID: "pcm_community_2017", leipzigCorpusBytes: 595_546),
  Language(
    name: "Egyptian Arabic", manifestISO: "arz", speakers: 118_400_000,
    leipzigCorpusID: "arz_wikipedia_2021_100K", leipzigCorpusBytes: 15_614_268),
  Language(
    name: "Marathi", manifestISO: "mar", speakers: 99_200_000,
    leipzigCorpusID: "mar-in_web_2015_100K", leipzigCorpusBytes: 17_707_576),
  Language(
    name: "Vietnamese", manifestISO: "vie", speakers: 97_100_000,
    leipzigCorpusID: "vie-vn_web_2015_100K", leipzigCorpusBytes: 24_913_750),
  Language(
    name: "Telugu", manifestISO: "tel", speakers: 95_900_000,
    leipzigCorpusID: "tel_news_2020_100K", leipzigCorpusBytes: 15_489_351),
  Language(
    name: "Swahili", manifestISO: "swh", speakers: 95_200_000,
    leipzigCorpusID: "swa_wikipedia_2021_100K", leipzigCorpusBytes: 18_605_546),
  Language(
    name: "Turkish", manifestISO: "tur", speakers: 93_700_000,
    leipzigCorpusID: "tur-tr_web_2019_100K", leipzigCorpusBytes: 21_708_869),
  Language(
    name: "Western Punjabi", manifestISO: "pnb", speakers: 90_400_000,
    leipzigCorpusID: "pnb_wikipedia_2021_100K", leipzigCorpusBytes: 21_174_861),
  Language(
    name: "Tagalog", manifestISO: "fil", speakers: 87_100_000,
    leipzigCorpusID: "tgl_wikipedia_2021_100K", leipzigCorpusBytes: 21_814_191),
  Language(
    name: "Tamil", manifestISO: "tam", speakers: 86_400_000,
    leipzigCorpusID: "tam_news_2020_100K", leipzigCorpusBytes: 18_762_207),
  // Leipzig has no Yue corpus; Macau web text is the closest.
  Language(
    name: "Yue Chinese", manifestISO: "yue", speakers: 85_800_000,
    leipzigCorpusID: "zho-mo_web_2016_100K", leipzigCorpusBytes: 46_765_442),
  Language(
    name: "Wu Chinese", manifestISO: "wuu", speakers: 83_300_000,
    leipzigCorpusID: "wuu_wikipedia_2021_100K", leipzigCorpusBytes: 22_415_795),
  Language(
    name: "Iranian Persian", manifestISO: "fas", speakers: 82_500_000,
    leipzigCorpusID: "fas-ir_web-public_2019_100K", leipzigCorpusBytes: 26_351_374),
  Language(
    name: "Korean", manifestISO: "kor", speakers: 82_200_000,
    leipzigCorpusID: "kor-kr_web_2020_100K", leipzigCorpusBytes: 26_301_916),
  Language(
    name: "Amharic", manifestISO: "amh", speakers: 78_000_000,
    leipzigCorpusID: "amh_wikipedia_2021_30K", leipzigCorpusBytes: 5_158_078),
  Language(
    name: "Thai", manifestISO: "tha", speakers: 71_400_000,
    leipzigCorpusID: "tha-th_web_2018_100K", leipzigCorpusBytes: 17_820_507),
  Language(
    name: "Javanese", manifestISO: "jav", speakers: 69_200_000,
    leipzigCorpusID: "jav_wikipedia_2021_100K", leipzigCorpusBytes: 19_040_130),
  Language(
    name: "Italian", manifestISO: "ita", speakers: 65_600_000,
    leipzigCorpusID: "ita-it_web-public_2019_100K", leipzigCorpusBytes: 24_817_589),
  Language(
    name: "Gujarati", manifestISO: "guj", speakers: 62_500_000,
    leipzigCorpusID: "guj_newscrawl_2016_100K", leipzigCorpusBytes: 21_354_731),
  Language(
    name: "Kannada", manifestISO: "kan", speakers: 58_700_000,
    leipzigCorpusID: "kan_newscrawl_2016_100K", leipzigCorpusBytes: 17_987_317),
  // Leipzig has no Levantine Arabic corpus; Egyptian Arabic is the closest.
  Language(
    name: "Levantine Arabic", manifestISO: "apc", speakers: 57_800_000,
    leipzigCorpusID: "arz_wikipedia_2021_100K", leipzigCorpusBytes: 15_614_268),
  Language(
    name: "Yoruba", manifestISO: "yor", speakers: 52_900_000,
    leipzigCorpusID: "yor_wikipedia_2021_10K", leipzigCorpusBytes: 2_275_742),
  // Leipzig has no Bhojpuri corpus; Hindi is the closest.
  Language(
    name: "Bhojpuri", manifestISO: "bho", speakers: 52_700_000,
    leipzigCorpusID: "hin_mixed_2019_100K", leipzigCorpusBytes: 23_434_441),
  Language(
    name: "Polish", manifestISO: "pol", speakers: 39_700_000,
    leipzigCorpusID: "pol_news_2023_100K", leipzigCorpusBytes: 21_295_904),
  Language(
    name: "Greek", manifestISO: "ell", speakers: 13_100_000,
    leipzigCorpusID: "ell_news_2023_100K", leipzigCorpusBytes: 28_110_694),
  Language(
    name: "Hebrew", manifestISO: "heb", speakers: 9_303_950,
    leipzigCorpusID: "heb_news_2020_100K", leipzigCorpusBytes: 22_421_266),
]

let excludedCategories: Set<Unicode.GeneralCategory> = [
  .spaceSeparator, .lineSeparator, .paragraphSeparator,
  .control, .format, .privateUse, .surrogate, .unassigned,
]
let excludedCSVCategories: Set<String> = ["Zs", "Zl", "Zp", "Cc", "Cf", "Co", "Cs", "Cn"]

// Per-language Leipzig corpora have at most 100K sentences, so a calibration
// anchor needs only a few Leipzig occurrences.
let leipzigAnchorMinCount = 8
let fineFreqAnchorMinCount = 1000
let minAnchors = 20

/// Folded characters are estimated once seen at least this often in Leipzig.
let foldEstimateMinLeipzigCount = 2

/// Romanized tables share their language's native-script corpus, whose few
/// Latin characters are incidental and can't calibrate them; below this fit
/// quality a table keeps its FineFreq distribution unchanged.
let minFitRSquared = 0.3

// MARK: - Errors

enum GeneratorError: Error, CustomStringConvertible {
  case http(URL, Int)
  case sizeMismatch(URL, expected: Int, actual: Int)
  case csv(String)
  case consistency(String)
  case process(String)
  case calibration(String)

  var description: String {
    switch self {
    case .http(let url, let status): return "HTTP \(status) fetching \(url)"
    case .sizeMismatch(let url, let expected, let actual):
      return "\(url): expected \(expected) bytes, got \(actual)"
    case .csv(let message): return "CSV error: \(message)"
    case .consistency(let message): return "consistency error: \(message)"
    case .process(let message): return "process error: \(message)"
    case .calibration(let message): return "calibration error: \(message)"
    }
  }
}

// MARK: - Downloading (cached under .build/character-frequencies/)

/// Uses `curl` because, unlike `URLSession`, it honors `HTTPS_PROXY`.
func download(from urlString: String, to path: URL, expectedBytes: Int? = nil) throws -> Data {
  if FileManager.default.fileExists(atPath: path.path) {
    let data = try Data(contentsOf: path)
    if let expectedBytes, data.count != expectedBytes {
      throw GeneratorError.sizeMismatch(
        URL(string: urlString) ?? path, expected: expectedBytes, actual: data.count)
    }
    return data
  }
  guard let url = URL(string: urlString) else {
    throw GeneratorError.consistency("malformed URL \(urlString)")
  }
  print("  downloading \(urlString)")
  try FileManager.default.createDirectory(
    at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
  let temp = path.appendingPathExtension("part")
  if FileManager.default.fileExists(atPath: temp.path) {
    try FileManager.default.removeItem(at: temp)
  }
  _ = try runProcess("/usr/bin/curl", ["-fsSL", "--retry", "0", urlString, "-o", temp.path])
  let data = try Data(contentsOf: temp)
  if let expectedBytes, data.count != expectedBytes {
    try? FileManager.default.removeItem(at: temp)
    throw GeneratorError.sizeMismatch(url, expected: expectedBytes, actual: data.count)
  }
  if FileManager.default.fileExists(atPath: path.path) {
    try FileManager.default.removeItem(at: path)
  }
  try FileManager.default.moveItem(at: temp, to: path)
  return data
}

/// Standard error passes through rather than into a pipe that nothing drains.
func runProcess(_ executable: String, _ arguments: [String]) throws -> Data {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  let outPipe = Pipe()
  process.standardOutput = outPipe
  try process.run()
  let data = outPipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw GeneratorError.process(
      "\(executable) \(arguments.joined(separator: " ")) exited \(process.terminationStatus)")
  }
  return data
}

// MARK: - RFC 4180 CSV parsing

/// Reads scalars rather than `Character`s so that a combining mark in a field
/// stays a separate code point from the delimiter or quote before it.
func parseCSV(_ text: String) -> [[String]] {
  var rows: [[String]] = []
  var row: [String] = []
  var field: [Unicode.Scalar] = []
  var quoted = false
  let scalars = Array(text.unicodeScalars)
  var i = 0
  func endField() {
    row.append(String(String.UnicodeScalarView(field)))
    field.removeAll(keepingCapacity: true)
  }
  func endRow() {
    endField()
    rows.append(row)
    row.removeAll(keepingCapacity: true)
  }
  while i < scalars.count {
    let c = scalars[i]
    if quoted {
      if c == "\"" {
        if i + 1 < scalars.count, scalars[i + 1] == "\"" {
          field.append("\"")
          i += 2
        } else {
          quoted = false
          i += 1
        }
      } else {
        field.append(c)
        i += 1
      }
    } else if c == "\"" {
      quoted = true
      i += 1
    } else if c == "," {
      endField()
      i += 1
    } else if c == "\n" {
      endRow()
      i += 1
    } else if c == "\r" {
      i += 1
    } else {
      field.append(c)
      i += 1
    }
  }
  if !field.isEmpty || !row.isEmpty {
    endRow()
  }
  return rows
}

func columnIndex(_ header: [String], _ name: String, context: String) throws -> Int {
  guard let index = header.firstIndex(of: name) else {
    throw GeneratorError.csv("\(context): missing column \(name)")
  }
  return index
}

// MARK: - FineFreq manifest

struct ManifestRow {
  let iso: String
  let code: String
  let totalFrequency: Int
}

func loadManifest() throws -> [ManifestRow] {
  let path = fineFreqCacheDir.appendingPathComponent("languages.csv")
  let data = try download(from: "\(fineFreqRawBase)/manifest/languages.csv", to: path)
  let table = parseCSV(String(decoding: data, as: UTF8.self))
  guard let header = table.first else { throw GeneratorError.csv("manifest: empty file") }
  let isoIndex = try columnIndex(header, "iso_639_3", context: "manifest")
  let codeIndex = try columnIndex(header, "language_code", context: "manifest")
  let freqIndex = try columnIndex(header, "total_frequency", context: "manifest")
  var rows: [ManifestRow] = []
  for record in table.dropFirst() where record.count > 1 {
    guard let freq = Int(record[freqIndex]) else {
      throw GeneratorError.csv("manifest: bad total_frequency \(record[freqIndex])")
    }
    rows.append(ManifestRow(iso: record[isoIndex], code: record[codeIndex], totalFrequency: freq))
  }
  return rows
}

func codes(for language: Language, manifest: [ManifestRow]) throws -> [(
  code: String, share: Double, manifestTotal: Int
)] {
  let matches = manifest.filter { $0.iso == language.manifestISO }.sorted { $0.code < $1.code }
  guard !matches.isEmpty else {
    throw GeneratorError.consistency(
      "\(language.name): no manifest rows for iso_639_3 \(language.manifestISO)")
  }
  let languageTotal = matches.reduce(0) { $0 + $1.totalFrequency }
  return matches.map {
    (
      code: $0.code, share: Double($0.totalFrequency) / Double(languageTotal),
      manifestTotal: $0.totalFrequency
    )
  }
}

// MARK: - FineFreq per-code tables

struct FineFreqTable {
  let code: String
  let counts: [Unicode.Scalar: Int]
  let visibleTotal: Int
  let probability: [Unicode.Scalar: Double]
}

func loadFineFreqTable(code: String, manifestTotal: Int) throws -> FineFreqTable {
  let path = fineFreqCacheDir.appendingPathComponent("csv").appendingPathComponent("\(code).csv")
  let data = try download(from: "\(fineFreqRawBase)/csv/\(code).csv", to: path)
  var text = String(decoding: data, as: UTF8.self)
  if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
  let table = parseCSV(text)
  guard let header = table.first else { throw GeneratorError.csv("\(code): empty CSV") }
  let charIndex = try columnIndex(header, "character", context: code)
  let categoryIndex = try columnIndex(header, "unicode_category", context: code)
  let freqIndex = try columnIndex(header, "total_frequency_all_time", context: code)
  let langIndex = try columnIndex(header, "language_code", context: code)

  var counts: [Unicode.Scalar: Int] = [:]
  var seen = Set<Unicode.Scalar>()
  var allTotal = 0
  var visibleRunningTotal = 0
  for record in table.dropFirst() where record.count > 1 {
    guard record[langIndex] == code else {
      throw GeneratorError.consistency("\(code): row for language_code \(record[langIndex])")
    }
    let field = record[charIndex]
    guard field.unicodeScalars.count == 1, let scalar = field.unicodeScalars.first else {
      throw GeneratorError.consistency(
        "\(code): non-scalar character field \(field.debugDescription)")
    }
    guard !seen.contains(scalar) else {
      throw GeneratorError.consistency(
        "\(code): duplicate character U+\(String(format: "%04X", scalar.value))")
    }
    seen.insert(scalar)
    guard let count = Int(record[freqIndex]) else {
      throw GeneratorError.consistency("\(code): bad total_frequency_all_time \(record[freqIndex])")
    }
    allTotal += count
    let category = record[categoryIndex]
    if !excludedCSVCategories.contains(category) {
      counts[scalar] = count
      visibleRunningTotal += count
    }
  }
  guard allTotal == manifestTotal else {
    throw GeneratorError.consistency(
      "\(code): CSV total_frequency_all_time sums to \(allTotal), manifest says \(manifestTotal)")
  }
  let visibleTotal = visibleRunningTotal
  guard visibleTotal > 0 else { throw GeneratorError.consistency("\(code): no visible characters") }
  var probability: [Unicode.Scalar: Double] = [:]
  for (scalar, count) in counts {
    probability[scalar] = Double(count) / Double(visibleTotal)
  }
  return FineFreqTable(
    code: code, counts: counts, visibleTotal: visibleTotal, probability: probability)
}

// MARK: - Leipzig corpora

/// Each sentence line starts with a numeric id and a tab, which are not counted.
func leipzigCounts(for language: Language) throws -> (
  counts: [Unicode.Scalar: Int], visibleTotal: Int
) {
  let tarPath = leipzigCacheDir.appendingPathComponent("\(language.leipzigCorpusID).tar.gz")
  _ = try download(
    from: "\(leipzigDownloadBase)/\(language.leipzigCorpusID).tar.gz", to: tarPath,
    expectedBytes: language.leipzigCorpusBytes)
  let listing = try runProcess("/usr/bin/tar", ["-tzf", tarPath.path])
  let members = String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init)
  let sentenceMembers = members.filter { $0.hasSuffix("-sentences.txt") }
  guard sentenceMembers.count == 1 else {
    throw GeneratorError.consistency(
      "\(language.leipzigCorpusID): expected exactly one *-sentences.txt member, found \(sentenceMembers)"
    )
  }
  let sentenceData = try runProcess(
    "/usr/bin/tar", ["-xzf", tarPath.path, "-O", sentenceMembers[0]])
  let text = String(decoding: sentenceData, as: UTF8.self)
  var counts: [Unicode.Scalar: Int] = [:]
  var visibleTotal = 0
  text.enumerateLines { line, _ in
    guard let tab = line.firstIndex(of: "\t") else { return }
    for scalar in line[line.index(after: tab)...].unicodeScalars {
      guard !excludedCategories.contains(scalar.properties.generalCategory) else { continue }
      counts[scalar, default: 0] += 1
      visibleTotal += 1
    }
  }
  return (counts, visibleTotal)
}

// MARK: - Numerically stable summation

/// Neumaier compensated summation. The result still depends on order at the
/// bit level, so callers never pass values in dictionary order.
func preciseSum(_ values: [Double]) -> Double {
  var sum = 0.0
  var compensation = 0.0
  for value in values {
    let t = sum + value
    if abs(sum) >= abs(value) {
      compensation += (sum - t) + value
    } else {
      compensation += (value - t) + sum
    }
    sum = t
  }
  return sum + compensation
}

func sumSorted(_ values: some Sequence<Double>) -> Double {
  preciseSum(values.sorted())
}

// MARK: - Calibration and un-folding

struct Fit {
  let a: Double
  let b: Double
  let rSquared: Double
  let anchors: Int
}

func calibrate(
  code: String, fineFreq: FineFreqTable, leipzig: [Unicode.Scalar: Int], leipzigVisibleTotal: Int
) throws -> Fit {
  var points: [(x: Double, y: Double)] = []
  for (scalar, leipzigCount) in leipzig where leipzigCount >= leipzigAnchorMinCount {
    guard let fineFreqCount = fineFreq.counts[scalar], fineFreqCount >= fineFreqAnchorMinCount
    else { continue }
    let x = log10(Double(leipzigCount) / Double(leipzigVisibleTotal))
    let y = log10(Double(fineFreqCount) / Double(fineFreq.visibleTotal))
    points.append((x, y))
  }
  points.sort { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
  guard points.count >= minAnchors else {
    throw GeneratorError.calibration(
      "\(code): only \(points.count) anchors (need >= \(minAnchors))")
  }
  let n = Double(points.count)
  let sx = preciseSum(points.map { $0.x })
  let sy = preciseSum(points.map { $0.y })
  let sxx = preciseSum(points.map { $0.x * $0.x })
  let sxy = preciseSum(points.map { $0.x * $0.y })
  let denominator = n * sxx - sx * sx
  guard denominator != 0 else {
    throw GeneratorError.calibration("\(code): degenerate anchors (zero variance in log Leipzig p)")
  }
  let a = (n * sxy - sx * sy) / denominator
  let b = (sy - a * sx) / n
  guard a.isFinite, b.isFinite else {
    throw GeneratorError.calibration("\(code): non-finite fit")
  }
  let meanY = sy / n
  let ssTotal = preciseSum(points.map { ($0.y - meanY) * ($0.y - meanY) })
  let ssResidual = preciseSum(
    points.map {
      let predicted = a * $0.x + b
      return ($0.y - predicted) * ($0.y - predicted)
    })
  let rSquared = ssTotal == 0 ? 1 : 1 - ssResidual / ssTotal
  return Fit(a: a, b: b, rSquared: rSquared, anchors: points.count)
}

struct FoldEstimate {
  let scalar: Unicode.Scalar
  let estimate: Double
}

/// FineFreq counted each NFKC-folded character as its expansion, so each
/// estimate is also subtracted from the scalars it expands to.
func unfold(
  code: String, fineFreq: FineFreqTable, leipzig: [Unicode.Scalar: Int], leipzigVisibleTotal: Int,
  fit: Fit
) throws -> (probability: [Unicode.Scalar: Double], estimates: [FoldEstimate]) {
  var candidates: [(scalar: Unicode.Scalar, count: Int)] = []
  for (scalar, count) in leipzig where count >= foldEstimateMinLeipzigCount {
    guard fineFreq.probability[scalar] == nil else { continue }
    let foldedScalars = Array(
      String(scalar).precomposedStringWithCompatibilityMapping.unicodeScalars)
    // Compares scalar arrays, not Strings: Swift's `String` `!=` tests Unicode
    // canonical equivalence, so a full composition exclusion (e.g. Devanagari
    // U+0958, which NFKC folds to U+0915 U+093C) reports equal to its own
    // single-scalar original even though the scalar sequence changed.
    guard foldedScalars != [scalar] else { continue }
    candidates.append((scalar, count))
  }
  // Expansions can share a scalar, and clamping at zero makes the subtraction
  // order matter.
  candidates.sort { $0.scalar.value < $1.scalar.value }

  var result = fineFreq.probability
  var estimates: [FoldEstimate] = []
  for (scalar, count) in candidates {
    let x = log10(Double(count) / Double(leipzigVisibleTotal))
    let estimate = pow(10, fit.a * x + fit.b)
    guard estimate.isFinite, estimate > 0, estimate < 1 else {
      throw GeneratorError.calibration(
        "\(code): implausible estimate \(estimate) for U+\(String(format: "%04X", scalar.value))")
    }
    let expansion = String(scalar).precomposedStringWithCompatibilityMapping
    var multiplicity: [Unicode.Scalar: Int] = [:]
    for expansionScalar in expansion.unicodeScalars
    where !excludedCategories.contains(expansionScalar.properties.generalCategory) {
      multiplicity[expansionScalar, default: 0] += 1
    }
    for expansionScalar in multiplicity.keys.sorted(by: { $0.value < $1.value }) {
      let subtrahend = estimate * Double(multiplicity[expansionScalar]!)
      result[expansionScalar] = max(0, (result[expansionScalar] ?? 0) - subtrahend)
    }
    result[scalar] = estimate
    estimates.append(FoldEstimate(scalar: scalar, estimate: estimate))
  }
  let total = sumSorted(result.values)
  guard total > 0 else {
    throw GeneratorError.consistency("\(code): distribution collapsed to zero")
  }
  for key in result.keys { result[key]! /= total }
  return (result, estimates)
}

// MARK: - Formatting

func hex(_ scalar: Unicode.Scalar) -> String { String(format: "%04X", scalar.value) }

func formatProbability(_ p: Double) -> String {
  String(format: "%.2e", p)
}

func unicodeName(_ scalar: Unicode.Scalar) -> String {
  scalar.properties.name ?? "U+\(hex(scalar))"
}

// MARK: - Main

struct CodeResult {
  let language: Language
  let code: String
  let weight: Double
  let before: [Unicode.Scalar: Double]
  let after: [Unicode.Scalar: Double]
  let estimates: [FoldEstimate]
}

func run() throws {
  print("Loading FineFreq manifest…")
  let manifest = try loadManifest()
  let totalSpeakers = languages.reduce(0) { $0 + $1.speakers }

  var results: [CodeResult] = []
  for language in languages {
    print("\(language.name)…")
    let languageCodes = try codes(for: language, manifest: manifest)
    let (leipzig, leipzigVisibleTotal) = try leipzigCounts(for: language)
    for entry in languageCodes {
      let fineFreq = try loadFineFreqTable(code: entry.code, manifestTotal: entry.manifestTotal)
      let fit = try calibrate(
        code: entry.code, fineFreq: fineFreq, leipzig: leipzig,
        leipzigVisibleTotal: leipzigVisibleTotal)
      let after: [Unicode.Scalar: Double]
      let estimates: [FoldEstimate]
      if fit.rSquared >= minFitRSquared {
        (after, estimates) = try unfold(
          code: entry.code, fineFreq: fineFreq, leipzig: leipzig,
          leipzigVisibleTotal: leipzigVisibleTotal, fit: fit)
      } else {
        after = fineFreq.probability
        estimates = []
      }
      let weight = Double(language.speakers) / Double(totalSpeakers) * entry.share
      results.append(
        CodeResult(
          language: language, code: entry.code, weight: weight, before: fineFreq.probability,
          after: after, estimates: estimates))
      let fitNote =
        fit.rSquared >= minFitRSquared ? "" : " (below R\u{00B2} floor, folding skipped)"
      print(
        "  \(entry.code): a=\(String(format: "%.4f", fit.a)) b=\(String(format: "%.4f", fit.b)) "
          + "R\u{00B2}=\(String(format: "%.4f", fit.rSquared)) anchors=\(fit.anchors) "
          + "estimates=\(estimates.count)\(fitNote)")
    }
  }

  // Each code adds to a scalar at most once, so these sums accumulate in the
  // fixed order of `results` regardless of dictionary iteration order.
  var globalBefore: [Unicode.Scalar: Double] = [:]
  var globalAfter: [Unicode.Scalar: Double] = [:]
  for result in results {
    for (scalar, p) in result.before { globalBefore[scalar, default: 0] += result.weight * p }
    for (scalar, p) in result.after { globalAfter[scalar, default: 0] += result.weight * p }
  }
  let total = sumSorted(globalAfter.values)
  guard abs(total - 1) < 1e-9 else {
    throw GeneratorError.consistency("global mix sums to \(total), expected 1")
  }

  let rows =
    globalAfter
    .filter { $0.value >= truncationFloor }
    .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.value < $1.key.value }

  var lines: [String] = [
    "# Generated by `make frequencies` — do not edit by hand.",
    "# FineFreq (Binbin Xu, arXiv:2512.09701, CC BY 4.0): https://github.com/Bin-2/FineFreq"
      + " — pinned commit \(fineFreqCommit); per-language character frequency tables from"
      + " FineWeb/FineWeb2 (Common Crawl, 2013-2025).",
    "# Leipzig Corpora Collection (D. Goldhahn, T. Eckart & U. Quasthoff, LREC 2012), CC BY 4.0:"
      + " https://wortschatz.uni-leipzig.de — non-normalized per-language sentence corpora, used"
      + " to estimate the characters FineFreq's own NFKC normalization discards; corpus ids per"
      + " language are pinned in this script.",
    "# Ethnologue: Languages of the World, 29th edition (2026), SIL Global, as reproduced in"
      + " Wikipedia's \"List of languages by total number of speakers\" (revision 1342700363)"
      + " — total speakers (L1+L2) for the top 40 languages by that count; Greek, Hebrew, and"
      + " Polish from Ethnologue's 22nd edition (2019) as recorded in Wikidata, first-language"
      + " only for Greek and Polish.",
    "# Method: each FineFreq table is normalized to a probability distribution over"
      + " non-whitespace, non-control, non-format, non-private-use, non-surrogate,"
      + " non-unassigned code points; characters NFKC folds out of FineFreq are estimated from a"
      + " Leipzig corpus calibrated onto FineFreq's scale, then un-folded back out of their NFKC"
      + " expansion; per-code distributions are mixed by Ethnologue speaker count times FineFreq"
      + " script share and truncated to a share >= \(formatProbability(truncationFloor)).",
  ]
  for (scalar, p) in rows {
    lines.append("\(hex(scalar))\t\(formatProbability(p))")
  }
  let outputURL = URL(fileURLWithPath: outputPath)
  try (lines.joined(separator: "\n") + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
  print("\nWrote \(rows.count) characters to \(outputPath)")

  printSummary(results: results, globalBefore: globalBefore, globalAfter: globalAfter)
}

func printSummary(
  results: [CodeResult], globalBefore: [Unicode.Scalar: Double],
  globalAfter: [Unicode.Scalar: Double]
) {
  print("\n== Largest folded-character estimates ==")
  let allEstimates = results.flatMap { result in
    result.estimates.map { (result: result, estimate: $0) }
  }
  let topEstimates = allEstimates.sorted { $0.estimate.estimate > $1.estimate.estimate }.prefix(20)
  for entry in topEstimates {
    let scalar = entry.estimate.scalar
    print(
      "  U+\(hex(scalar)) \(unicodeName(scalar)) in \(entry.result.code) "
        + "(\(entry.result.language.name)): p\u{2248}\(formatProbability(entry.estimate.estimate))")
  }

  print("\n== ASCII punctuation: global p before vs. after un-folding ==")
  let sample: [Unicode.Scalar] = [",", "!", "?", "~", ":", "(", ")", "."]
  for scalar in sample {
    let before = globalBefore[scalar] ?? 0
    let after = globalAfter[scalar] ?? 0
    print(
      "  \(String(scalar)): before=\(formatProbability(before)) after=\(formatProbability(after))")
  }
}

do {
  try run()
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}
