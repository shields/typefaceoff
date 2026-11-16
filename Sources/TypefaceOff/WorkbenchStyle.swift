import AppKit
import SwiftUI

enum WorkbenchStyle {
  static let paper = Color(red: 251 / 255, green: 252 / 255, blue: 253 / 255)
  static let ink = Color(red: 27 / 255, green: 28 / 255, blue: 31 / 255)
  static let secondaryInk = Color(nsColor: adaptive(0x5a5e66, contrast: 0x3f4248))
  static let track = Color(nsColor: adaptive(0x8e939b, contrast: 0x5a5e66))
  static let fieldUnderline = Color(nsColor: adaptive(0x8e939b, contrast: 0x1b1c1f))
  static let hairline = Color(nsColor: adaptive(0xc9ccd2, contrast: 0x8e939b))
  static let panel = Color(red: 45 / 255, green: 48 / 255, blue: 54 / 255)
  static let toolbar = Color(red: 39 / 255, green: 42 / 255, blue: 48 / 255)
  static let accent = Color(red: 101 / 255, green: 138 / 255, blue: 175 / 255)
  static let sheet = Color(red: 246 / 255, green: 247 / 255, blue: 249 / 255)
  static let border = Color(red: 201 / 255, green: 207 / 255, blue: 218 / 255)
  static let red = adaptive(0xb43b43, contrast: 0x8f2530)
  static let blue = adaptive(0x286b9d, contrast: 0x1a527d)

  static func increasedContrast(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.aqua, .accessibilityHighContrastAqua])
      == .accessibilityHighContrastAqua
  }

  @MainActor static func useLightAppearance(increasedContrast: Bool) {
    NSApp.appearance = NSAppearance(
      named: increasedContrast ? .accessibilityHighContrastAqua : .aqua)
  }

  private static func adaptive(_ normal: Int, contrast: Int) -> NSColor {
    NSColor(name: nil) { appearance in
      let rgb = increasedContrast(appearance) ? contrast : normal
      return NSColor(
        calibratedRed: CGFloat((rgb >> 16) & 255) / 255,
        green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
  }
}
