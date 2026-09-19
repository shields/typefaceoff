import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite @MainActor struct SpecimenScrollTests {
  @Test func scrollingIsProportionalInBothDirectionsAndSurvivesRecreation() {
    let position = SpecimenScrollPosition()
    let a = scrollView(height: 1200)
    let b = scrollView(height: 2200)
    position.attach(a)
    position.attach(b)
    scroll(a, to: 0.4)
    #expect(abs(progress(b) - 0.4) < 0.001)
    scroll(b, to: 0.7)
    #expect(abs(progress(a) - 0.7) < 0.001)
    position.detach(a)
    position.detach(b)
    let restored = scrollView(height: 1200)
    position.attach(restored)
    #expect(abs(progress(restored) - 0.7) < 0.001)
    let lateLayout = scrollView(height: 0)
    position.attach(lateLayout)
    lateLayout.documentView?.setFrameSize(NSSize(width: 300, height: 2200))
    #expect(abs(progress(lateLayout) - 0.7) < 0.001)
  }

  @Test func resizingAndShortSpecimensDoNotResetTheReadingPosition() {
    let position = SpecimenScrollPosition()
    let a = scrollView(height: 1200)
    let b = scrollView(height: 100)
    position.attach(a)
    position.attach(b)
    scroll(a, to: 0.6)
    #expect(b.contentView.bounds.minY == 0)
    a.setFrameSize(NSSize(width: 300, height: 400))
    a.layoutSubtreeIfNeeded()
    #expect(abs(progress(a) - 0.6) < 0.001)
    position.preserveDuringUpdate {
      a.documentView?.setFrameSize(NSSize(width: 300, height: 100))
      a.contentView.scroll(to: .zero)
      a.documentView?.setFrameSize(NSSize(width: 300, height: 1800))
    }
    #expect(abs(progress(a) - 0.6) < 0.001)
    b.documentView?.setFrameSize(NSSize(width: 300, height: 2200))
    #expect(abs(progress(b) - 0.6) < 0.001)
  }

  @Test func workbenchRestoresScrollingAfterInspectingACharacter() async throws {
    _ = NSApplication.shared
    var comparison = Comparison()
    comparison.sample = .custom
    comparison.customText = String(
      repeating: "A passage with different line lengths and sizes.\n", count: 80)
    comparison.b?.size = 44
    let document = WorkbenchDocument(comparison: comparison)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1440, height: 800), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: WorkbenchView(document: document))
    window.contentView = host
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    let original = specimens(in: host)
    #expect(original.count == 2)
    let a = try #require(original.first?.enclosingScrollView)
    let b = try #require(original.last?.enclosingScrollView)
    #expect(a.documentView!.frame.height != b.documentView!.frame.height)
    scroll(a, to: 0.4)
    #expect(abs(progress(b) - 0.4) < 0.001)
    original.first?.select("x")
    try await Task.sleep(for: .milliseconds(100))
    #expect(document.comparison.mode == .glyph)
    #expect(specimens(in: host).isEmpty)
    document.edit("Return to text", undoManager: nil) { $0.mode = .text }
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    let restored = specimens(in: host)
    #expect(restored.count == 2)
    for specimen in restored {
      let scroll = try #require(specimen.enclosingScrollView)
      #expect(abs(progress(scroll) - 0.4) < 0.001)
    }
    document.edit("Resize type", undoManager: nil) { $0.b?.size = 18 }
    window.setContentSize(NSSize(width: 1250, height: 650))
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    for specimen in specimens(in: host) {
      let scroll = try #require(specimen.enclosingScrollView)
      #expect(abs(progress(scroll) - 0.4) < 0.001)
    }
  }

  private func scrollView(height: Double) -> NSScrollView {
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    scroll.documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 300, height: height))
    scroll.layoutSubtreeIfNeeded()
    return scroll
  }

  private func scroll(_ view: NSScrollView, to fraction: Double) {
    let extent = max(0, (view.documentView?.frame.height ?? 0) - view.contentView.bounds.height)
    view.contentView.scroll(to: NSPoint(x: 0, y: fraction * extent))
    view.reflectScrolledClipView(view.contentView)
  }

  private func progress(_ scroll: NSScrollView) -> Double {
    scroll.contentView.bounds.minY
      / max(1, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
  }

  private func specimens(in view: NSView) -> [SpecimenNSTextView] {
    if let specimen = view as? SpecimenNSTextView { return [specimen] }
    return view.subviews.flatMap { specimens(in: $0) }
  }
}

@MainActor private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}
