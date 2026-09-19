import AppKit
import SwiftUI
import TypefaceCore

/// Use the same shaping attributes as the specimen, including kerning and ligatures.
struct FontPreviewText: NSViewRepresentable {
  let config: FontConfiguration
  let text: String

  func makeNSView(context: Context) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.lineBreakMode = .byClipping
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
  }

  func updateNSView(_ label: NSTextField, context: Context) {
    label.attributedStringValue = Self.content(config: config, text: text)
    label.toolTip =
      FontRenderer.supports(text, config: config) ? nil : "Unavailable: \(unicodeDescription(text))"
  }

  static func content(config: FontConfiguration, text: String) -> NSAttributedString {
    guard FontRenderer.supports(text, config: config) else {
      return NSAttributedString(
        string: "Unavailable",
        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemOrange])
    }
    var attributes = FontRenderer.attributes(config, size: 21)
    attributes[.foregroundColor] = NSColor.labelColor
    return NSAttributedString(string: text, attributes: attributes)
  }
}
