import AppKit
import SwiftUI
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct SpecificationSliderTests {
  @Test func nativeAccessibilityAndKeyboardUseRealValuesOnALogarithmicTrack() throws {
    let slider = SpecificationSliderView()
    var values: [Double] = []
    slider.change = { values.append($0) }
    #expect(slider.accessibilityValue() as? Double == 22)
    #expect(slider.accessibilityMinValue() as? Double == 10)
    #expect(slider.accessibilityMaxValue() as? Double == 144)
    #expect(slider.accessibilityPerformIncrement())
    #expect(values.last == 23)
    #expect(slider.accessibilityPerformDecrement())
    #expect(values.last == 22)
    slider.setAccessibilityValue(42)
    #expect(values.last == 42 && slider.doubleValue < 0.6)
    slider.setAccessibilityValue("invalid")
    slider.setAccessibilityValue(200)
    #expect(values.last == 42)
    slider.isEnabled = false
    #expect(!slider.accessibilityPerformIncrement())
    slider.setAccessibilityValue(30)
    #expect(values.last == 42)
    slider.isEnabled = true
    for key in [UInt16(123), 125, 124, 126] {
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
          isARepeat: false, keyCode: key))
      slider.keyDown(with: event)
    }
    #expect(values.suffix(4) == [32, 22, 32, 42])
    slider.keyDown(
      with: try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
          isARepeat: false, keyCode: 48)))
    slider.doubleValue = 0.5
    slider.adjust()
    #expect(abs(try #require(values.last) - sqrt(1440)) < 0.001)
    slider.setting = .axis(tagNumber("test"))
    slider.rules = .init(range: 0.0001...0.0004, step: 0.0001)
    slider.doubleValue = 1
    slider.adjust()
    #expect(values.last == 0.0004)
    #expect(SpecificationSliderView(coder: NSCoder()) == nil)
  }

  @Test func draggingGroupsUndoAndDisabledEnvironmentReachesNativeControls() async throws {
    let model = WorkbenchModel()
    let host = WorkbenchTestHost(
      ComparisonInspector(model: model, state: model.inspector).preferredColorScheme(.light)
        .disabled(false),
      width: 320, height: 700)
    defer { host.window.close() }
    try await host.settle()
    let slider = try #require(
      host.subviews.compactMap { $0 as? SpecificationSliderView }.first {
        $0.accessibilityIdentifier() == "Font A Size"
      })
    for (type, x) in [
      (NSEvent.EventType.leftMouseUp, 0.7), (.leftMouseDragged, 0.7), (.leftMouseDragged, 0.6),
    ] {
      NSApp.postEvent(try mouseEvent(type, fraction: x, slider: slider), atStart: true)
    }
    slider.mouseDown(with: try mouseEvent(.leftMouseDown, fraction: 0.7, slider: slider))
    #expect(model.comparison.a.size > 40)
    host.window.undoManager?.undo()
    #expect(model.comparison.a.size == 22 && model.comparison.b?.size == 22)
    host.setContent(
      ComparisonInspector(model: model, state: model.inspector).preferredColorScheme(.light)
        .disabled(true))
    try await host.settle()
    #expect(!slider.isEnabled)
    #expect(
      host.subviews.compactMap { $0 as? SpecificationFieldView }.allSatisfy { !$0.field.isEnabled })
  }

  private func mouseEvent(_ type: NSEvent.EventType, fraction: Double, slider: NSSlider) throws
    -> NSEvent
  {
    try #require(
      NSEvent.mouseEvent(
        with: type,
        location: slider.convert(
          NSPoint(x: slider.bounds.width * fraction, y: slider.bounds.midY), to: nil),
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: slider.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 1))
  }
}
