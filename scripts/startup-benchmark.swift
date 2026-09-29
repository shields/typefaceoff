import CryptoKit
import Foundation

struct BenchmarkError: Error, CustomStringConvertible {
  let description: String
}

func benchmark() throws {
  let environment = ProcessInfo.processInfo.environment
  guard let app = environment["STARTUP_APP"], let output = environment["STARTUP_OUTPUT"],
    let runs = Int(environment["STARTUP_RUNS"] ?? "7"), runs > 0
  else {
    throw BenchmarkError(
      description: "Set STARTUP_APP, STARTUP_OUTPUT, and a positive STARTUP_RUNS.")
  }
  let outputURL = URL(fileURLWithPath: output)
  try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  // Do not leave an old successful report behind if a launch fails.
  if FileManager.default.fileExists(atPath: output) {
    try FileManager.default.removeItem(at: outputURL)
  }
  let executableURL = URL(fileURLWithPath: app).appendingPathComponent("Contents/MacOS/TypefaceOff")
  let executableHash = SHA256.hash(data: try Data(contentsOf: executableURL))
    .map { String(format: "%02x", $0) }.joined()
  let logURL = outputURL.appendingPathExtension("log")
  FileManager.default.createFile(atPath: logURL.path, contents: nil)
  let log = try FileHandle(forWritingTo: logURL)
  defer { try? log.close() }
  var samples: [[String: Double]] = []
  var warmup: [String: Double] = [:]
  for iteration in 0...runs {
    let process = Process()
    process.executableURL = executableURL
    // Keep every run at the same window size and bypass saved AppKit window state.
    process.arguments = ["-ApplePersistenceIgnoreState", "YES"]
    var childEnvironment = environment
    childEnvironment.removeValue(forKey: "TYPEFACEOFF_TESTING")
    childEnvironment.removeValue(forKey: "TYPEFACEOFF_STARTUP_PROFILE")
    process.environment = childEnvironment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = log
    let start = ProcessInfo.processInfo.systemUptime
    try process.run()
    while process.isRunning, ProcessInfo.processInfo.systemUptime - start < 30 {
      Thread.sleep(forTimeInterval: 0.01)
    }
    guard !process.isRunning else {
      process.terminate()
      // A hung main thread might not handle termination. Reap this child even on failure.
      Thread.sleep(forTimeInterval: 0.1)
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      process.waitUntilExit()
      throw BenchmarkError(description: "Launch \(iteration) timed out; see \(logURL.path).")
    }
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw BenchmarkError(description: "Launch \(iteration) failed; see \(logURL.path).")
    }
    let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let prefix = "TYPEFACEOFF_STARTUP "
    guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
      throw BenchmarkError(description: "Launch \(iteration) produced no startup measurements.")
    }
    let timestamps = try JSONDecoder().decode(
      [String: Double].self, from: Data(line.dropFirst(prefix.count).utf8))
    let sample = timestamps.mapValues { ($0 - start) * 1000 }
    guard let firstFrame = sample["firstFrame"], let settled = sample["settled"],
      sample.values.allSatisfy({ $0.isFinite && $0 >= 0 }), settled >= firstFrame
    else {
      throw BenchmarkError(description: "Invalid startup measurements in launch \(iteration).")
    }
    if iteration > 0, sample.keys.sorted() != warmup.keys.sorted() {
      throw BenchmarkError(description: "Inconsistent startup milestones in launch \(iteration).")
    }
    print(
      String(
        format: "%@ first frame %.1f ms; settled %.1f ms",
        iteration == 0 ? "warmup" : "run \(iteration)", firstFrame, settled))
    if iteration == 0 { warmup = sample } else { samples.append(sample) }
  }
  var summary: [String: [String: Double]] = [:]
  for key in samples[0].keys.sorted() {
    let values = samples.map { $0[key]! }.sorted()
    let middle = values.count / 2
    summary[key] = [
      "median": values.count.isMultiple(of: 2)
        ? (values[middle - 1] + values[middle]) / 2 : values[middle],
      "p90": values[Int(ceil(Double(values.count) * 0.9)) - 1],
      "min": values[0], "max": values[values.count - 1],
    ]
  }
  let report: [String: Any] = [
    "schemaVersion": 1,
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "processors": ProcessInfo.processInfo.processorCount,
    "revision": environment["STARTUP_REVISION"] ?? "unknown",
    "executableSHA256": executableHash,
    "configuration": "StartupBenchmark (-O, no coverage, app sandbox enabled)",
    "cachePolicy": "Fresh processes; one excluded warmup; OS and font caches are not flushed.",
    "unit": "milliseconds from process launch",
    "warmup": warmup, "samples": samples, "summary": summary,
  ]
  try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: outputURL, options: .atomic)
  print(
    String(
      format: "median first frame %.1f ms; settled %.1f ms",
      summary["firstFrame"]!["median"]!, summary["settled"]!["median"]!))
  print("Saved \(outputURL.path)")
}

do {
  try benchmark()
} catch {
  FileHandle.standardError.write(Data("Startup benchmark failed: \(error)\n".utf8))
  exit(1)
}
