import SwiftUI
import TypefaceCore

@MainActor
final class FeaturePreviewModel: ObservableObject {
  struct Result {
    let config: FontConfiguration
    let previews: [String: FontFeaturePreview]
  }

  @Published private(set) var result: Result?
  private var request = UUID()
  private let load: @Sendable (FontConfiguration) async throws -> [String: FontFeaturePreview]

  init(engine: FontFeaturePreviewEngine = .shared) {
    load = { try await engine.previews(config: $0) }
  }

  init(load: @escaping @Sendable (FontConfiguration) async throws -> [String: FontFeaturePreview]) {
    self.load = load
  }

  func update(_ config: FontConfiguration?) async {
    let fuzzWork = FuzzDiagnostics.shared.beginWork("feature-preview")
    defer {
      FuzzDiagnostics.shared.endWork(
        fuzzWork, kind: "feature-preview", outcome: Task.isCancelled ? "cancelled" : "completed")
    }
    let request = UUID()
    self.request = request
    result = nil
    guard let config else { return }
    #if TYPEFACEOFF_STARTUP_BENCHMARK
      StartupDiagnostics.mark("previewRequested-\(config.postScriptName)")
    #endif
    do {
      try await Task.sleep(for: .milliseconds(120))
      #if TYPEFACEOFF_STARTUP_BENCHMARK
        StartupDiagnostics.mark("previewSearchStarted-\(config.postScriptName)")
      #endif
      let previews = try await load(config)
      try Task.checkCancellation()
      guard self.request == request else { return }
      result = Result(config: config, previews: previews)
      #if TYPEFACEOFF_STARTUP_BENCHMARK
        StartupDiagnostics.mark("preview-\(config.postScriptName)")
      #endif
    } catch {
      // Cancelled or superseded searches must not replace the current configuration's previews.
    }
  }
}
