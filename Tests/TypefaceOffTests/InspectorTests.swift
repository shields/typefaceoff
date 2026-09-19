import AppKit
import SwiftUI
import Testing

@testable import TypefaceOff

@Suite @MainActor struct InspectorTests {
  @Test func collapsingRetainsTheInspectorAndItsScrollPosition() async throws {
    _ = NSApplication.shared
    let document = WorkbenchDocument()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: Fixture(document: document, visible: true))
    window.contentView = host
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    let inspector = try #require(scrollView(in: host))
    inspector.contentView.scroll(to: NSPoint(x: 0, y: 100))
    inspector.reflectScrolledClipView(inspector.contentView)
    let position = inspector.contentView.bounds.origin
    #expect(position.y > 0)
    host.rootView = Fixture(document: document, visible: false)
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    #expect(scrollView(in: host) === inspector)
    host.rootView = Fixture(document: document, visible: true)
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
    let document: WorkbenchDocument
    let visible: Bool
    var body: some View {
      HStack(spacing: 0) {
        InspectorPanel(document: document, side: .a, isVisible: visible)
        Color.white
      }.frame(width: 700, height: 500)
    }
  }
}
