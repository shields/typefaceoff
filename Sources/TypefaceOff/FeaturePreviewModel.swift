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
    let request = UUID()
    self.request = request
    result = nil
    guard let config else { return }
    do {
      try await Task.sleep(for: .milliseconds(120))
      let previews = try await load(config)
      try Task.checkCancellation()
      guard self.request == request else { return }
      result = Result(config: config, previews: previews)
    } catch {
      // Cancelled or superseded searches must not replace the current configuration's previews.
    }
  }
}
