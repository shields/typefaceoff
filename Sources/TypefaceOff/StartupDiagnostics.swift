#if TYPEFACEOFF_STARTUP_BENCHMARK
  import AppKit
  import Synchronization

  /// Compiled only into the opt-in launch benchmark. Times share the driver's monotonic clock,
  /// so they include process creation and framework loading before App.init.
  @MainActor
  enum StartupDiagnostics {
    private static var milestones: [String: Double] = [:]
    private static var drawnSpecimens: Set<String> = []
    private static var finishing = false
    nonisolated private static let backgroundMilestones = Mutex<[String: Double]>([:])

    nonisolated static func markBackground(_ name: String) {
      let timestamp = ProcessInfo.processInfo.systemUptime
      backgroundMilestones.withLock {
        if $0[name] == nil { $0[name] = timestamp }
      }
    }

    static func mark(_ name: String) {
      guard milestones[name] == nil else { return }
      milestones[name] = ProcessInfo.processInfo.systemUptime
      finishIfReady()
    }

    static func specimenDrawn(_ view: NSView) {
      guard view.window?.isVisible == true, !view.visibleRect.isEmpty,
        let label = view.accessibilityLabel(),
        ["Font A specimen", "Font B specimen"].contains(label)
      else { return }
      drawnSpecimens.insert(label)
      if drawnSpecimens.count == 2, milestones["firstFrame"] == nil {
        // Return to the main queue after both text views have actually drawn.
        DispatchQueue.main.async { mark("firstFrame") }
      }
    }

    private static func finishIfReady() {
      let required = ["firstFrame", "rankingReady", "preview-HelveticaNeue", "preview-ArialMT"]
      guard !finishing, required.allSatisfy({ milestones[$0] != nil }) else { return }
      finishing = true
      DispatchQueue.main.async {
        // Include the layout and display of the asynchronously produced results.
        for window in NSApp.windows where window.isVisible {
          window.contentView?.layoutSubtreeIfNeeded()
          window.displayIfNeeded()
        }
        milestones["settled"] = ProcessInfo.processInfo.systemUptime
        milestones.merge(backgroundMilestones.withLock { $0 }) { existing, _ in existing }
        let data = try! JSONSerialization.data(withJSONObject: milestones, options: [.sortedKeys])
        FileHandle.standardOutput.write(
          Data(("TYPEFACEOFF_STARTUP " + String(decoding: data, as: UTF8.self) + "\n").utf8))
        // The sampling driver owns this process and terminates it after collecting the profile.
        if ProcessInfo.processInfo.environment["TYPEFACEOFF_STARTUP_PROFILE"] != "1" {
          NSApp.terminate(nil)
        }
      }
    }
  }
#endif
