import AppKit
import SwiftUI
import TypefaceCore

struct SpecificationField: NSViewRepresentable {
  let label: String
  let identifier: String
  let value: Double
  let precision: Int
  let unit: String
  let automatic: Bool
  let rules: SpecificationValue
  let numberWidth: CGFloat
  var enabled = true
  let commit: (SpecificationValue.Entry, Bool) -> Bool
  @Environment(\.locale) private var locale

  func makeNSView(context: Context) -> SpecificationFieldView {
    SpecificationFieldView(commit: commit)
  }

  func updateNSView(_ view: SpecificationFieldView, context: Context) {
    view.configure(
      label: label, identifier: identifier, value: value, precision: precision, unit: unit,
      automatic: automatic, rules: rules, numberWidth: numberWidth, enabled: enabled,
      locale: locale, commit: commit)
  }
}

final class SpecificationFieldView: NSView, NSTextFieldDelegate {
  let field = NSTextField()
  let unitLabel = NSTextField(labelWithString: "")
  let stepper = NSStepper()
  private var tracking: NSTrackingArea?
  private(set) var editing = false
  private(set) var hovering = false
  private var hasDraft = false
  private var value = 0.0
  private var precision = 0
  private var automatic = false
  private var unit = ""
  private var numberWidth = 0.0
  private var locale = Locale.current
  private var rules = SpecificationValue(range: 0...1, step: 1)
  private var commit: (SpecificationValue.Entry, Bool) -> Bool

  init(commit: @escaping (SpecificationValue.Entry, Bool) -> Bool) {
    self.commit = commit
    super.init(frame: .zero)
    field.cell = SpecificationNumberCell(textCell: "")
    field.isEditable = true
    field.isSelectable = true
    field.usesSingleLineMode = true
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.alignment = .right
    field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    field.delegate = self
    unitLabel.font = .systemFont(ofSize: 13)
    unitLabel.textColor = NSColor(WorkbenchStyle.secondaryInk)
    unitLabel.setAccessibilityElement(false)
    stepper.controlSize = .mini
    stepper.minValue = -1
    stepper.maxValue = 1
    stepper.increment = 1
    stepper.target = self
    stepper.action = #selector(step(_:))
    addSubview(field)
    addSubview(unitLabel)
    addSubview(stepper)
  }

  required init?(coder: NSCoder) { nil }

  func configure(
    label: String, identifier: String, value: Double, precision: Int, unit: String,
    automatic: Bool, rules: SpecificationValue, numberWidth: CGFloat, enabled: Bool,
    locale: Locale, commit: @escaping (SpecificationValue.Entry, Bool) -> Bool
  ) {
    self.value = value
    self.precision = precision
    self.unit = unit
    self.automatic = automatic
    self.rules = rules
    self.numberWidth = numberWidth
    self.locale = locale
    self.commit = commit
    field.isEnabled = enabled
    field.setAccessibilityLabel(label)
    field.setAccessibilityIdentifier(identifier)
    field.setAccessibilityHelp(
      "\(rules.range.lowerBound)–\(rules.range.upperBound) \(unit). Option-Return sets both fonts.")
    stepper.setAccessibilityLabel("Step \(label)")
    stepper.setAccessibilityIdentifier("\(identifier) stepper")
    stepper.isEnabled = enabled
    if !hasDraft { restore() }
    updateAppearance()
    needsLayout = true
  }

  override func layout() {
    super.layout()
    field.frame = NSRect(x: 3, y: 3, width: numberWidth + 6, height: 18)
    unitLabel.frame = NSRect(x: numberWidth + 10, y: 3, width: 34, height: 18)
    stepper.frame = NSRect(x: bounds.maxX - 17, y: 1, width: 15, height: 22)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    hovering = true
    updateAppearance()
  }

  override func mouseExited(with event: NSEvent) {
    hovering = false
    updateAppearance()
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    if field.isEnabled { addCursorRect(bounds, cursor: .iBeam) }
  }

  override func mouseDown(with event: NSEvent) {
    if field.isEnabled { window?.makeFirstResponder(field) }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if field.isEnabled {
      NSColor(WorkbenchStyle.track).setStroke()
      let line = NSBezierPath()
      line.move(to: NSPoint(x: 6, y: 3))
      line.line(to: NSPoint(x: numberWidth + 6, y: 3))
      line.lineWidth = 1
      line.stroke()
      if editing || hovering {
        NSGraphicsContext.saveGraphicsState()
        NSFocusRingPlacement.only.set()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
      }
    }
  }

  func controlTextDidBeginEditing(_ notification: Notification) {
    editing = true
    updateAppearance()
  }

  func controlTextDidChange(_ notification: Notification) { hasDraft = true }

  func controlTextDidEndEditing(_ notification: Notification) {
    editing = false
    if hasDraft { submit(both: false) }
    updateAppearance()
  }

  func control(
    _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
  ) -> Bool {
    guard !textView.hasMarkedText() else { return false }
    let modifiers = NSEvent.modifierFlags
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)),
      #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
      submit(both: modifiers.contains(.option))
    case #selector(NSResponder.moveUp(_:)),
      #selector(NSResponder.moveUpAndModifySelection(_:)),
      #selector(NSResponder.moveToBeginningOfParagraph(_:)),
      #selector(NSResponder.moveToBeginningOfParagraphAndModifySelection(_:)):
      increment(1, modifiers: modifiers)
    case #selector(NSResponder.moveDown(_:)),
      #selector(NSResponder.moveDownAndModifySelection(_:)),
      #selector(NSResponder.moveToEndOfParagraph(_:)),
      #selector(NSResponder.moveToEndOfParagraphAndModifySelection(_:)):
      increment(-1, modifiers: modifiers)
    case #selector(NSResponder.cancelOperation(_:)):
      hasDraft = false
      restore()
      window?.makeFirstResponder(nil)
    default: return false
    }
    return true
  }

  func submit(both: Bool) {
    guard field.isEnabled else { return }
    hasDraft = false
    guard let entry = rules.entry(field.stringValue, locale: locale) else {
      NSSound.beep()
      restore()
      return
    }
    guard commit(entry, both) else {
      NSSound.beep()
      restore()
      return
    }
    if case .number(let number) = entry {
      value = number
      precision = max(precision, SpecificationNumber.precision([number]))
    }
    restore()
  }

  func increment(_ direction: Int, modifiers: NSEvent.ModifierFlags) {
    guard field.isEnabled else { return }
    let start = SpecificationNumber.parse(field.stringValue, locale: locale) ?? value
    let next = rules.stepping(
      start, direction: direction, shift: modifiers.contains(.shift),
      option: modifiers.contains(.option))
    guard commit(.number(next), false) else {
      NSSound.beep()
      restore()
      return
    }
    hasDraft = false
    value = next
    precision = max(precision, SpecificationNumber.precision([next]))
    restore()
  }

  @objc private func step(_ sender: NSStepper) {
    increment(Int(sender.doubleValue), modifiers: NSEvent.modifierFlags)
    sender.doubleValue = 0
  }

  private func restore() {
    field.stringValue = SpecificationNumber.format(value, precision: precision, locale: locale)
    let units = unit == "pt" ? "points" : unit
    field.setAccessibilityValueDescription(
      "\(automatic ? "automatic, " : "")\(field.stringValue) \(units)")
  }

  private func updateAppearance() {
    unitLabel.stringValue = automatic ? "auto" : unit
    field.textColor = NSColor(automatic ? WorkbenchStyle.secondaryInk : WorkbenchStyle.ink)
    stepper.isHidden = !field.isEnabled || !(editing || hovering)
    needsDisplay = true
  }
}

private final class SpecificationNumberCell: NSTextFieldCell {
  private lazy var editor: NSTextView = {
    let editor = NSTextView()
    editor.isFieldEditor = true
    return editor
  }()

  override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }

  override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
    let editor = super.setUpFieldEditorAttributes(textObj)
    (editor as? NSTextView)?.enabledTextCheckingTypes = 0
    return editor
  }
}
