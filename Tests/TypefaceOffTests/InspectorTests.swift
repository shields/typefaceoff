import AppKit
import SwiftUI
import Testing

@testable import TypefaceOff

@Suite @MainActor struct InspectorTests {
  @Test func collapsingRetainsTheInspectorAndItsScrollPosition() async throws {
    _ = NSApplication.shared
    let model = WorkbenchModel()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: Fixture(model: model, visible: true))
    window.contentView = host
    window.orderFront(nil)
    try await waitUntil {
      host.layoutSubtreeIfNeeded()
      guard let scroll = scrollView(in: host), let document = scroll.documentView else {
        return false
      }
      return document.frame.height > scroll.contentView.bounds.height
    }
    let inspector = try #require(scrollView(in: host))
    inspector.contentView.scroll(to: NSPoint(x: 0, y: 100))
    inspector.reflectScrolledClipView(inspector.contentView)
    let position = inspector.contentView.bounds.origin
    #expect(position.y > 0)
    host.rootView = Fixture(model: model, visible: false)
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    #expect(scrollView(in: host) === inspector)
    host.rootView = Fixture(model: model, visible: true)
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    #expect(scrollView(in: host) === inspector)
    #expect(inspector.contentView.bounds.origin == position)
  }

  private func scrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
  }

  private struct Fixture: View {
    let model: WorkbenchModel
    let visible: Bool
    var body: some View {
      HStack(spacing: 0) {
        InspectorPanel(model: model, side: .a, isVisible: visible)
        Color.white
      }.frame(width: 700, height: 500)
    }
  }
}
