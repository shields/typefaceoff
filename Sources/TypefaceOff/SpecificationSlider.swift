// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import SwiftUI
import TypefaceCore

struct SpecificationSlider: NSViewRepresentable {
  let setting: SpecificationSetting
  let rules: SpecificationValue
  let value: Double
  let automatic: Bool
  let identifier: String
  let change: (Double) -> Void
  let editing: (Bool) -> Void
  @Environment(\.isEnabled) private var enabled

  func makeNSView(context: Context) -> SpecificationSliderView { SpecificationSliderView() }

  func updateNSView(_ slider: SpecificationSliderView, context: Context) {
    slider.setting = setting
    slider.rules = rules
    slider.value = value
    slider.doubleValue = setting.position(value, in: rules.range)
    slider.change = change
    slider.editing = editing
    slider.isEnabled = enabled
    (slider.cell as! SpecificationSliderCell).automatic = automatic
    slider.setAccessibilityLabel(identifier)
    slider.setAccessibilityIdentifier(identifier)
    slider.setAccessibilityValueDescription(
      "\(automatic ? "automatic, " : "")\(SpecificationNumber.format(value, precision: 3))")
    slider.toolTip = automatic ? "Drag to set explicit leading and turn Auto off" : nil
    slider.needsDisplay = true
  }
}

final class SpecificationSliderView: NSSlider {
  var setting = SpecificationSetting.size
  var rules = SpecificationValue(range: 10...144, step: 1)
  var value = 22.0
  var change: ((Double) -> Void)?
  var editing: ((Bool) -> Void)?

  init() {
    super.init(frame: .zero)
    cell = SpecificationSliderCell()
    minValue = 0
    maxValue = 1
    isContinuous = true
    target = self
    action = #selector(adjust)
  }

  required init?(coder: NSCoder) { nil }

  @objc func adjust() {
    value = setting.value(at: doubleValue, in: rules.range)
    change?(value)
  }

  override func mouseDown(with event: NSEvent) {
    editing?(true)
    super.mouseDown(with: event)
    editing?(false)
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 123, 125: increment(-1, modifiers: event.modifierFlags)
    case 124, 126: increment(1, modifiers: event.modifierFlags)
    default: super.keyDown(with: event)
    }
  }

  override func accessibilityValue() -> Any? { value }
  override func setAccessibilityValue(_ value: Any?) {
    guard isEnabled, let number = value as? NSNumber, rules.range.contains(number.doubleValue)
    else {
      return
    }
    self.value = number.doubleValue
    doubleValue = setting.position(self.value, in: rules.range)
    change?(self.value)
  }
  override func accessibilityMinValue() -> Any? { rules.range.lowerBound }
  override func accessibilityMaxValue() -> Any? { rules.range.upperBound }
  override func accessibilityPerformIncrement() -> Bool { increment(1, modifiers: []) }
  override func accessibilityPerformDecrement() -> Bool { increment(-1, modifiers: []) }

  @discardableResult
  private func increment(_ direction: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
    guard isEnabled else { return false }
    value = rules.stepping(
      value, direction: direction, shift: modifiers.contains(.shift),
      option: modifiers.contains(.option))
    doubleValue = setting.position(value, in: rules.range)
    change?(value)
    return true
  }
}

final class SpecificationSliderCell: NSSliderCell {
  var automatic = false

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let track = NSRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3)
    NSColor(WorkbenchStyle.hairline).setFill()
    NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
    if !automatic {
      var filled = track
      filled.size.width *= doubleValue
      NSColor(WorkbenchStyle.secondaryInk).setFill()
      NSBezierPath(roundedRect: filled, xRadius: 1.5, yRadius: 1.5).fill()
    }
  }

  override func drawKnob(_ knobRect: NSRect) {
    let rect = NSRect(x: knobRect.midX - 6.5, y: knobRect.midY - 6.5, width: 13, height: 13)
    let knob = NSBezierPath(ovalIn: rect)
    NSColor(WorkbenchStyle.paper).setFill()
    knob.fill()
    NSColor(automatic ? WorkbenchStyle.hairline : WorkbenchStyle.track).setStroke()
    knob.lineWidth = 1
    knob.stroke()
  }
}
