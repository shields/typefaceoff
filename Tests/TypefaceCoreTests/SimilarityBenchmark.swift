import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import TypefaceCore

extension Trait where Self == ConditionTrait {
  static var benchmark: Self {
    .enabled(if: ProcessInfo.processInfo.environment["TYPEFACEOFF_BENCHMARK_DIR"] != nil)
  }
}

/// Opt-in artifacts use only installed fonts and stay on the local machine.
@Suite(.serialized) struct SimilarityBenchmark {
  struct RankingTiming: Encodable {
    let workers: Int
    let seconds: Double
    let scores: [String: SimilarityScore]
  }

  @Test(.benchmark)
  func compareSerialAndParallelFamilyRanking() async throws {
    let installed = FontCatalog()
    let names = [
      "Arial", "Helvetica Neue", "Times New Roman", "Georgia", "Courier New", "Verdana",
      "Trebuchet MS", "Skia", "Avenir", "Baskerville", "Palatino", "Menlo", "Optima", "Times",
    ]
    let configs = names.compactMap { installed.defaultConfiguration(in: $0, size: 22) }
    let catalog = FontCatalog(
      descriptors: configs.map {
        CTFontDescriptorCreateWithNameAndSize($0.postScriptName as CFString, 22)
      })
    let reference = try #require(configs.first { $0.face.family == "Helvetica Neue" })
    var timings: [RankingTiming] = []
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let workerCounts = Array(Set([1, min(4, cores), cores])).sorted()
    // Fresh rendering caches for each run; reverse order to reduce warm-up bias.
    for workers in workerCounts + workerCounts.reversed() {
      let engine = FontSimilarityEngine(rankingConcurrency: workers)
      let start = ContinuousClock.now
      var scores: [String: SimilarityScore] = [:]
      for try await result in await engine.rankFamilies(reference: reference, catalog: catalog) {
        let score: SimilarityScore = try #require(result.score)
        scores[result.family] = score
      }
      timings.append(.init(workers: workers, seconds: seconds(since: start), scores: scores))
      #expect(scores == timings[0].scores)
      #expect(scores.count == catalog.families.count)
    }
    let folder = try benchmarkFolder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(timings).write(to: folder.appendingPathComponent("ranking-timings.json"))
  }

  struct Row: Codable {
    let id: Int
    let a: FontConfiguration
    let b: FontConfiguration
    let components: SimilarityScore
    let distances: [String: Double]
    let seconds: [String: Double]
  }
  struct Fit: Codable {
    let a: FontConfiguration
    let b: FontConfiguration
    let proposed: FontConfiguration
    let before: SimilarityScore
    let after: SimilarityScore
    let evaluations: Int
    let seconds: Double
  }
  struct Triplet: Codable {
    let id: Int
    let reference: String
    let left: String
    let right: String
    let size: Double
    let leftRow: Int
    let rightRow: Int
  }
  struct Report: Encodable {
    let scoreVersion = SimilarityScore.version
    let corpusVersion = SimilarityCorpus.version
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let processors = ProcessInfo.processInfo.processorCount
    let scale = 2.0
    let glyphs = SimilarityCorpus.diagnostic.glyphs
    let runs = SimilarityCorpus.diagnostic.runs
    let rows: [Row]
    let fits: [Fit]
    let triplets: [Triplet]
  }

  @Test(.benchmark)
  func compareAlgorithmsAndExportBlindReview() async throws {
    let folder = try benchmarkFolder()
    let catalog = FontCatalog()
    let families = [
      "Arial", "Helvetica Neue", "Times New Roman", "Georgia", "Courier New", "Verdana",
      "Trebuchet MS", "Skia",
    ]
    var rows: [Row] = []
    var triplets: [Triplet] = []
    var fits: [Fit] = []
    for size in [14.0, 22.0, 36.0] {
      let configs = families.compactMap { catalog.defaultConfiguration(in: $0, size: size) }
      let engine = FontSimilarityEngine()
      for config in configs {
        try specimen(config, url: folder.appendingPathComponent(imageName(config)))
      }
      for reference in configs.prefix(3) {
        var referenceRows: [Int] = []
        for candidate in configs where candidate.postScriptName != reference.postScriptName {
          let start = ContinuousClock.now
          let score = try await engine.compare(a: reference, b: candidate)
          let hybridTime = seconds(since: start)
          let oldStart = ContinuousClock.now
          let old = SimilarityCorpus.diagnostic.glyphs.map {
            Differences.compare($0, a: reference, b: candidate).shape
          }
          let oldTime = seconds(since: oldStart)
          let ssimStart = ContinuousClock.now
          let baseline = try structuralSimilarity(a: reference, b: candidate)
          let structuralTime = seconds(since: ssimStart)
          let index = rows.count
          referenceRows.append(index)
          rows.append(
            Row(
              id: index, a: reference, b: candidate, components: score,
              distances: [
                "currentIoU": old.reduce(0, +) / Double(old.count), "SDF": score.geometry,
                "multiscaleInk": (score.appearance + score.shapedText) / 2,
                "SSIM": baseline.ssim, "MS-SSIM": baseline.multiscale, "hybrid": score.total,
              ],
              seconds: [
                "hybrid": hybridTime, "currentIoU": oldTime, "SSIM+MS-SSIM": structuralTime,
              ]))
        }
        // Fixed, reproducible order; identities and algorithm predictions are hidden in the review.
        for index in 0..<referenceRows.count {
          let first = referenceRows[index]
          let second = referenceRows[(index + 1) % referenceRows.count]
          let left = index.isMultiple(of: 2) ? first : second
          let right = index.isMultiple(of: 2) ? second : first
          triplets.append(
            Triplet(
              id: triplets.count, reference: imageName(reference),
              left: imageName(rows[left].b), right: imageName(rows[right].b), size: size,
              leftRow: left, rightRow: right))
        }
      }
    }
    let variable = try #require(catalog.defaultConfiguration(in: "Skia", size: 22))
    var target = variable
    target.axes[tagNumber("wght")] = 1.2
    target.axes[tagNumber("wdth")] = 1.05
    target.tracking = 0.025
    for (a, b) in [
      (target, variable), (FontConfiguration("HelveticaNeue"), FontConfiguration("ArialMT")),
    ] {
      let engine = FontFitEngine()
      let corpus = SimilarityCorpus.fitting(
        reference: a, candidate: b, text: "Hamburg minimum AV To fi fl 1820")
      for refine in [false, true] {
        let start = ContinuousClock.now
        var final: FontFitResult?
        for try await result in await engine.fit(
          a: a, b: b, options: .init(config: b), corpus: corpus,
          catalog: catalog, budget: refine ? .refine : .quick, refine: refine)
        { final = result }
        let result = try #require(final)
        #expect(result.score.total <= result.originalScore.total)
        fits.append(
          Fit(
            a: a, b: b, proposed: result.proposed, before: result.originalScore,
            after: result.score, evaluations: result.evaluations, seconds: seconds(since: start)))
      }
    }
    let report = Report(rows: rows, fits: fits, triplets: triplets)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    try data.write(to: folder.appendingPathComponent("scores.json"))
    let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
    try html(json: json).write(
      to: folder.appendingPathComponent("review.html"), atomically: true, encoding: .utf8)
  }

  func benchmarkFolder() throws -> URL {
    let folder = URL(
      fileURLWithPath: try #require(
        ProcessInfo.processInfo.environment["TYPEFACEOFF_BENCHMARK_DIR"]))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  func seconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now).components
    return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
  }

  private func imageName(_ config: FontConfiguration) -> String {
    "\(config.postScriptName)-\(Int(config.size)).png"
  }

  private func specimen(_ config: FontConfiguration, url: URL) throws {
    let scale = 2.0
    let width = 1600
    let height = Int((config.size * 2 + 24) * scale)
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    context.setShouldSmoothFonts(false)
    context.textPosition = CGPoint(x: 12, y: config.size / 2 + 12)
    CTLineDraw(
      FontRenderer.line(
        "Hamburg minimum AV To fi fl 1820", config: config, size: config.size, tracking: true),
      context)
    let image = try #require(context.makeImage())
    let destination = try #require(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
  }

  private func structuralSimilarity(a: FontConfiguration, b: FontConfiguration) throws -> (
    ssim: Double, multiscale: Double
  ) {
    var ssim = 0.0
    var multiscale = 0.0
    let texts = SimilarityCorpus.diagnostic.glyphs + SimilarityCorpus.diagnostic.runs
    for text in texts {
      let left = try SimilarityImage.render(text, config: a, scale: 2, tracking: true, radius: 8)
      let right = try SimilarityImage.render(text, config: b, scale: 2, tracking: true, radius: 8)
      let x = min(left.x, right.x)
      let y = min(left.y, right.y)
      var width = max(left.x + left.width, right.x + right.width) - x
      var height = max(left.y + left.height, right.y + right.height) - y
      var l = (0..<width * height).map {
        1 - left.value(left.pixels, x: $0 % width + x, y: $0 / width + y)
      }
      var r = (0..<width * height).map {
        1 - right.value(right.pixels, x: $0 % width + x, y: $0 / width + y)
      }
      let weights = [0.0448, 0.2856, 0.3001, 0.2363, 0.1333]
      var product = 1.0
      for level in 0..<weights.count {
        let measure = localSSIM(l, r, width: width, height: height)
        if level == 0 { ssim += 1 - measure.ssim }
        product *= pow(max(0, level == 4 ? measure.ssim : measure.cs), weights[level])
        l = downsample(l, width: width, height: height)
        r = downsample(r, width: width, height: height)
        width = max(1, width / 2)
        height = max(1, height / 2)
      }
      multiscale += 1 - product
    }
    return (ssim / Double(texts.count), multiscale / Double(texts.count))
  }

  /// Gaussian 11×11 windows, standard SSIM constants, and replicated edges.
  private func localSSIM(_ a: [Float], _ b: [Float], width: Int, height: Int) -> (
    ssim: Double, cs: Double
  ) {
    func blur(_ input: [Float]) -> [Float] {
      let paddedWidth = width + 10
      let paddedHeight = height + 10
      let padded = (0..<paddedWidth * paddedHeight).map { index in
        input[
          min(height - 1, max(0, index / paddedWidth - 5)) * width
            + min(width - 1, max(0, index % paddedWidth - 5))]
      }
      let result = SimilarityImage.blur(
        padded, width: paddedWidth, height: paddedHeight, sigma: 1.5)
      return (0..<width * height).map { result[($0 / width + 5) * paddedWidth + $0 % width + 5] }
    }
    let ma = blur(a)
    let mb = blur(b)
    let aa = blur(a.map { $0 * $0 })
    let bb = blur(b.map { $0 * $0 })
    let ab = blur(zip(a, b).map { $0 * $1 })
    var total = 0.0
    var contrast = 0.0
    for index in a.indices {
      let x = Double(ma[index])
      let y = Double(mb[index])
      let variance = max(0, Double(aa[index]) - x * x) + max(0, Double(bb[index]) - y * y)
      let cs = (2 * (Double(ab[index]) - x * y) + 0.0009) / (variance + 0.0009)
      total += (2 * x * y + 0.0001) / (x * x + y * y + 0.0001) * cs
      contrast += cs
    }
    return (min(1, max(0, total / Double(a.count))), min(1, max(0, contrast / Double(a.count))))
  }

  private func downsample(_ values: [Float], width: Int, height: Int) -> [Float] {
    let nextWidth = max(1, width / 2)
    return (0..<nextWidth * max(1, height / 2)).map { index in
      let x = index % nextWidth * 2
      let y = index / nextWidth * 2
      return (0..<2).flatMap { dy in
        (0..<2).map { dx in values[min(height - 1, y + dy) * width + min(width - 1, x + dx)] }
      }.reduce(0, +) / 4
    }
  }

  private func html(json: String) -> String {
    #"""
    <!doctype html><html lang="en"><meta charset="utf-8"><title>Font similarity review</title>
    <style>body{font:16px system-ui;margin:32px auto;max-width:850px;padding:0 20px}img{display:block;width:800px;max-width:100%;border:1px solid #ccc}button,input{font:inherit;margin:6px;padding:8px}label{display:block}pre{white-space:pre-wrap}fieldset{border:0;padding:0}small{color:#555}</style>
    <h1>Font similarity review</h1>
    <p>Which candidate looks closer to the reference? Compare shape, weight, spacing, and proportions. All three use the same point size and default settings. Identities and scores are hidden.</p>
    <label>Reviewer code <input id="reviewer" value="reviewer-1"></label>
    <p id="progress"></p><small>Reference</small><img id="reference" alt="Reference specimen">
    <small>Left candidate</small><img id="left" alt="Left candidate"><small>Right candidate</small><img id="right" alt="Right candidate">
    <fieldset id="choices"><button data-choice="left">Left is closer</button><button data-choice="tie">Tie</button><button data-choice="right">Right is closer</button></fieldset>
    <button id="previous">Previous</button><button id="next">Skip / next</button><button id="download">Download judgments</button>
    <p>Answers remain in this page until downloaded. Nothing is uploaded. Import one or more downloaded files to calculate individual and majority agreement.</p>
    <input id="imports" type="file" accept="application/json" multiple><button id="evaluate">Evaluate agreement</button><pre id="evaluation"></pre>
    <script type="application/json" id="data">\#(json)</script>
    <script>
    const report=JSON.parse(document.querySelector('#data').textContent), triplets=report.triplets, answers={}, imported=[];
    let index=0;
    const element=id=>document.getElementById(id);
    // Includes exact score/configuration data: judgments from a different run cannot be mixed.
    const manifest=JSON.stringify(report.rows.map(row=>[row.a,row.b,row.distances]));
    function show(){const t=triplets[index]; for(const key of ['reference','left','right']) element(key).src=t[key];
      element('progress').textContent=`${index+1} / ${triplets.length} · ${t.size} pt · ${Object.keys(answers).length} answered${answers[t.id]?' · Saved: '+answers[t.id]:''}`;}
    element('choices').onclick=event=>{const choice=event.target.dataset.choice;if(!choice)return;answers[triplets[index].id]=choice;index=Math.min(index+1,triplets.length-1);show();};
    element('previous').onclick=()=>{index=Math.max(0,index-1);show();}; element('next').onclick=()=>{index=(index+1)%triplets.length;show();};
    function current(){return {manifest,reviewer:element('reviewer').value,answers:{...answers}};}
    element('download').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(current(),null,2)],{type:'application/json'}));const link=document.createElement('a');link.href=url;link.download='font-judgments.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
    element('imports').onchange=async event=>{imported.length=0;try{for(const file of event.target.files){const data=JSON.parse(await file.text());if(data.manifest!==manifest)throw Error('Judgments belong to a different benchmark run.');imported.push(data);}element('evaluation').textContent=`Imported ${imported.length} files.`;}catch(error){imported.length=0;element('evaluation').textContent=error.message;}};
    element('evaluate').onclick=()=>{const byReviewer=new Map(imported.map(item=>[item.reviewer,item]));if(Object.keys(answers).length)byReviewer.set(current().reviewer,current());const sets=[...byReviewer.values()];
      const valid=new Set(['left','right','tie']);const majority={};for(const t of triplets){const counts={left:0,right:0,tie:0};for(const set of sets){const value=set.answers[t.id];if(valid.has(value))counts[value]++;}const order=Object.entries(counts).sort((a,b)=>b[1]-a[1]);if(order[0][1])majority[t.id]=order[0][1]===order[1][1]?'tie':order[0][0];}
      function agreement(answers){const result={};for(const algorithm of Object.keys(report.rows[0].distances)){let n=0,correct=0;for(const t of triplets){if(!valid.has(answers[t.id]))continue;const d=report.rows[t.leftRow].distances[algorithm]-report.rows[t.rightRow].distances[algorithm];const prediction=Math.abs(d)<1e-9?'tie':d<0?'left':'right';correct+=Number(prediction===answers[t.id]);n++;}result[algorithm]={correct,total:n,agreement:n?correct/n:null};}return result;}
      element('evaluation').textContent=JSON.stringify({individual:sets.map(set=>({reviewer:set.reviewer,agreement:agreement(set.answers)})),majority:agreement(majority),tiePolicy:'Exact agreement; tied human votes count as a tie. Algorithm tolerance 1e-9.'},null,2);};show();
    </script></html>
    """#
  }
}
