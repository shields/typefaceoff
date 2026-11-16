import AppKit
import CoreText
import SwiftUI
import TypefaceCore

struct LanguageCharacterSheet: NSViewRepresentable {
  let tokens: [String]
  let comparison: Comparison
  let columns: Int
  let summary: String

  var height: Double {
    Double((tokens.count + columns - 1) / columns) * (comparison.b == nil ? 28 : 50)
  }

  func makeNSView(context: Context) -> LanguageCharacterSheetView {
    LanguageCharacterSheetView()
  }

  func updateNSView(_ view: LanguageCharacterSheetView, context: Context) {
    view.update(tokens: tokens, comparison: comparison, columns: columns)
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.image)
    view.setAccessibilityLabel(summary)
  }
}

final class LanguageCharacterSheetView: NSView {
  private struct Key: Equatable {
    let tokens: [ExactText]
    let a: FontConfiguration
    let b: FontConfiguration?
  }
  private var key: Key?
  private(set) var lines: [[CTLine?]] = []
  private(set) var columns = 28
  private var installed: [Bool] = []
  override var isFlipped: Bool { true }

  func update(tokens: [String], comparison: Comparison, columns: Int) {
    self.columns = columns
    let key = Key(tokens: tokens.map(ExactText.init), a: comparison.a, b: comparison.b)
    if self.key != key {
      self.key = key
      let configurations = [comparison.a, comparison.b].compactMap { $0 }
      installed = configurations.map(FontRenderer.isAvailable)
      lines = configurations.map { config in
        var attributes = FontRenderer.attributes(config, size: 17)
        attributes[.foregroundColor] = NSColor(WorkbenchStyle.ink)
        return tokens.map { token in
          guard FontRenderer.supports(token, config: config) else { return nil }
          return CTLineCreateWithAttributedString(
            NSAttributedString(string: token, attributes: attributes))
        }
      }
    }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    for (side, row) in lines.enumerated() {
      for (index, line) in row.enumerated() {
        let cell = NSRect(
          x: 24 + Double(index % columns) * 22,
          y: Double(index / columns) * (lines.count == 1 ? 28 : 50) + Double(side) * 22,
          width: 22, height: 22)
        guard cell.intersects(dirtyRect) else { continue }
        if index.isMultiple(of: columns) {
          let color =
            installed[side]
            ? side == 0 ? WorkbenchStyle.red : WorkbenchStyle.blue
            : NSColor(WorkbenchStyle.secondaryInk)
          ((side == 0 ? "A" : "B") as NSString).draw(
            at: CGPoint(x: 0, y: cell.minY + 3),
            withAttributes: [
              .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: color,
            ])
        }
        context.saveGState()
        context.clip(to: cell)
        if let line {
          let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
          context.translateBy(x: cell.midX - ink.midX, y: cell.minY + 17)
          context.scaleBy(x: 1, y: -1)
          context.textMatrix = .identity
          context.textPosition = .zero
          CTLineDraw(line, context)
        } else {
          context.setStrokeColor(NSColor(WorkbenchStyle.track).cgColor)
          context.setLineWidth(1)
          context.setLineDash(phase: 0, lengths: [1.5, 2])
          context.addPath(
            CGPath(
              roundedRect: cell.insetBy(dx: 2, dy: 2), cornerWidth: 3, cornerHeight: 3,
              transform: nil))
          context.strokePath()
        }
        context.restoreGState()
      }
    }
  }
}
