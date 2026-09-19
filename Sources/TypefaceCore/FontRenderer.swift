import CoreGraphics
import CoreText
import Foundation

public struct GlyphMeasurement: Sendable {
  public let bounds: CGRect
  public let advance: Double
  public var leftBearing: Double { bounds.minX }
  public var rightBearing: Double { advance - bounds.maxX }
}

public enum FontRenderer {
  public static func font(_ config: FontConfiguration, size: Double? = nil) -> CTFont {
    var settings: [[CFString: Any]] = []
    for (key, value) in config.features.sorted(by: { $0.key < $1.key }) {
      let parts = key.split(separator: ".")
      if parts.first == "ot", parts.count == 2 {
        settings.append([
          kCTFontOpenTypeFeatureTag: String(parts[1]), kCTFontOpenTypeFeatureValue: value,
        ])
      } else if parts.first == "aat", parts.count >= 2, let type = Int(parts[1]) {
        settings.append([
          kCTFontFeatureTypeIdentifierKey: type, kCTFontFeatureSelectorIdentifierKey: value,
        ])
      }
    }
    let attributes: [CFString: Any] = [
      kCTFontNameAttribute: config.postScriptName,
      kCTFontVariationAttribute: Dictionary(
        uniqueKeysWithValues: config.axes.map {
          (NSNumber(value: $0.key), NSNumber(value: $0.value))
        }),
      kCTFontFeatureSettingsAttribute: settings,
      kCTFontCascadeListAttribute: [],
    ]
    let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, size ?? config.size, nil)
  }

  public static func attributes(
    _ config: FontConfiguration, size: Double? = nil, tracking: Bool = true
  ) -> [NSAttributedString.Key: Any] {
    var result: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font(config, size: size)
    ]
    if config.features["ot.kern"] == 0 {
      result[NSAttributedString.Key(kCTKernAttributeName as String)] = 0
    }
    if let ligatures = config.features["ot.liga"] {
      result[NSAttributedString.Key(kCTLigatureAttributeName as String)] = ligatures
    } else if let ligatures = config.features["aat.1.2"] {
      result[NSAttributedString.Key(kCTLigatureAttributeName as String)] = ligatures == 2 ? 1 : 0
    }
    if tracking, config.tracking != 0 {
      result[NSAttributedString.Key(kCTTrackingAttributeName as String)] =
        config.tracking * (size ?? config.size)
    }
    return result
  }

  public static func line(
    _ text: String, config: FontConfiguration, size: Double, tracking: Bool = false
  ) -> CTLine {
    CTLineCreateWithAttributedString(
      NSAttributedString(
        string: text, attributes: attributes(config, size: size, tracking: tracking)))
  }

  public static func isAvailable(_ config: FontConfiguration) -> Bool {
    // Applying variation coordinates can change a named instance's PostScript name.
    CTFontCopyPostScriptName(CTFontCreateWithName(config.postScriptName as CFString, 22, nil))
      as String == config.postScriptName
  }

  public static func supports(_ text: String, config: FontConfiguration) -> Bool {
    guard isAvailable(config) else { return false }
    let configuredName = CTFontCopyPostScriptName(font(config, size: 22)) as String
    let shaped = line(text, config: config, size: 22)
    // Core Text guarantees that this array contains CTRun objects.
    let runs = CTLineGetGlyphRuns(shaped) as! [CTRun]
    return runs.allSatisfy { run in
      let attrs = CTRunGetAttributes(run) as NSDictionary
      guard let actual = attrs[kCTFontAttributeName] else { return false }
      let runFont = actual as! CTFont
      guard CTFontCopyPostScriptName(runFont) as String == configuredName else {
        return false
      }
      let count = CTRunGetGlyphCount(run)
      var glyphs = [CGGlyph](repeating: 0, count: count)
      CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
      return !glyphs.contains(0)
    }
  }

  public static func measure(
    _ text: String, config: FontConfiguration, size: Double, tracking: Bool = false
  )
    -> GlyphMeasurement
  {
    let shaped = line(text, config: config, size: size, tracking: tracking)
    let bounds = CTLineGetBoundsWithOptions(shaped, [.useGlyphPathBounds])
    return GlyphMeasurement(
      bounds: bounds.isNull ? .zero : bounds,
      advance: CTLineGetTypographicBounds(shaped, nil, nil, nil))
  }

  public static func nativeMetrics(_ text: String, config: FontConfiguration) -> GlyphMeasurement {
    measure(text, config: config, size: Double(CTFontGetUnitsPerEm(font(config))))
  }

  /// The selected font's x-height, in native units unless a point size is supplied.
  public static func xHeight(config: FontConfiguration, size: Double? = nil) -> Double? {
    guard supports("x", config: config) else { return nil }
    return measure("x", config: config, size: size ?? Double(CTFontGetUnitsPerEm(font(config))))
      .bounds.height
  }

  public static func mask(
    _ text: String, config: FontConfiguration, size: Double, width: Int, height: Int,
    origin: CGPoint
  ) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: width * height)
    pixels.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return }
      context.setShouldAntialias(true)
      context.setShouldSmoothFonts(false)
      context.setFillColor(gray: 1, alpha: 1)
      context.textPosition = origin
      var attrs = attributes(config, size: size, tracking: false)
      attrs[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = CGColor(
        gray: 1, alpha: 1)
      CTLineDraw(
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs)),
        context)
    }
    return pixels
  }

  /// A shared envelope that is independent of the glyph currently being inspected.
  public static func envelope(a: FontConfiguration, b: FontConfiguration?, sample: String)
    -> GlyphMeasurement
  {
    var bounds = CGRect(x: 0, y: -25, width: 100, height: 125)
    var advance = 100.0
    let candidates = Set(
      (String((33...126).compactMap(UnicodeScalar.init).map(Character.init)) + "ÁÅÉgj" + sample)
        .map(String.init))
    for config in [a, b].compactMap({ $0 }) {
      for glyph in candidates where supports(glyph, config: config) {
        let metric = measure(glyph, config: config, size: 100 * config.size / a.size)
        bounds = bounds.union(metric.bounds)
        advance = max(advance, metric.advance + config.tracking * 100 * config.size / a.size)
      }
    }
    return GlyphMeasurement(bounds: bounds, advance: advance)
  }
}
