import AppKit
import CoreText
import SwiftUI
import TypefaceCore

/// Use the same shaping attributes as the specimen, including kerning and ligatures.
struct FontPreviewText: NSViewRepresentable {
  let config: FontConfiguration
  let text: String
  let size: CGFloat

  func makeNSView(context: Context) -> FontPreviewDrawingView { FontPreviewDrawingView() }

  func updateNSView(_ label: FontPreviewDrawingView, context: Context) {
    label.content = Self.content(config: config, text: text, size: size)
    label.toolTip =
      FontRenderer.supports(text, config: config) ? nil : "Unavailable: \(unicodeDescription(text))"
  }

  static func content(config: FontConfiguration, text: String, size: CGFloat = 21)
    -> NSAttributedString
  {
    guard FontRenderer.supports(text, config: config) else {
      return NSAttributedString(
        string: "Unavailable",
        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemOrange])
    }
    var attributes = FontRenderer.attributes(config, size: size)
    attributes[.foregroundColor] = NSColor.labelColor
    return NSAttributedString(string: text, attributes: attributes)
  }
}

/// Draw the verified Core Text line directly so AppKit cannot reshape a label differently.
final class FontPreviewDrawingView: NSView {
  var content = NSAttributedString(string: "") {
    didSet {
      setAccessibilityElement(true)
      setAccessibilityRole(.staticText)
      setAccessibilityLabel(content.string)
      needsDisplay = true
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let line = CTLineCreateWithAttributedString(content)
    let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    context.saveGState()
    context.clip(to: bounds)
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: max(0, -ink.minX), y: 7)
    CTLineDraw(line, context)
    context.restoreGState()
  }
}
