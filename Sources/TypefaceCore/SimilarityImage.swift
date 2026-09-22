import Accelerate
import CoreGraphics
import CoreText
import Foundation

/// Images retain their integer pixel coordinates relative to the text origin and baseline.
/// Rows run bottom-to-top, so row zero is at the minimum baseline-relative y coordinate.
struct SimilarityImage: Sendable {
  let x: Int
  let y: Int
  let width: Int
  let height: Int
  let pixels: [Float]
  let field: [Float]
  let blurred: [[Float]]
  let radius: Float
  let measurement: GlyphMeasurement
  var byteCount: Int { pixels.count * MemoryLayout<Float>.stride * 4 }

  init(
    x: Int = 0, y: Int = 0, width: Int, height: Int, pixels: [Float], radius: Float,
    measurement: GlyphMeasurement = .init(bounds: .zero, advance: 0)
  ) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.pixels = pixels
    self.radius = radius
    self.measurement = measurement
    field = Self.signedField(pixels, width: width, height: height, radius: radius)
    blurred = [0.75, 1.5].map { Self.blur(pixels, width: width, height: height, sigma: $0) }
  }

  static func render(
    _ text: String, config: FontConfiguration, scale: Double, tracking: Bool, radius: Float
  ) throws -> Self {
    guard FontRenderer.supports(text, config: config, size: config.size, tracking: tracking) else {
      throw SimilarityError.unsupportedText(config.postScriptName, text)
    }
    let line = FontRenderer.line(text, config: config, size: config.size, tracking: tracking)
    let measurement = FontRenderer.measure(line)
    let bounds = measurement.bounds
    let padding = Double(ceil(radius)) + 5
    let left = floor(bounds.minX * scale) - padding
    let bottom = floor(bounds.minY * scale) - padding
    let w = max(1, ceil(bounds.maxX * scale) - left + padding)
    let h = max(1, ceil(bounds.maxY * scale) - bottom + padding)
    // Bound allocation before converting font-controlled dimensions to integers.
    guard left.isFinite, bottom.isFinite, w.isFinite, h.isFinite,
      abs(left) < 1_000_000, abs(bottom) < 1_000_000, w * h <= 4_194_304
    else { throw SimilarityError.renderingFailed }
    let width = Int(w)
    let height = Int(h)
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let rendered = rgba.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue)
      else { return false }
      context.setShouldAntialias(true)
      context.setShouldSmoothFonts(false)
      context.translateBy(x: -left, y: -bottom)
      context.scaleBy(x: scale, y: scale)
      context.textPosition = .zero
      CTLineDraw(line, context)
      return true
    }
    guard rendered else { throw SimilarityError.renderingFailed }
    // Quartz bitmap rows run top-to-bottom; value() uses baseline-relative y-up coordinates.
    var pixels = [Float](repeating: 0, count: width * height)
    for row in 0..<height {
      let source = (height - 1 - row) * width * 4
      for column in 0..<width {
        pixels[row * width + column] = Float(rgba[source + column * 4 + 3]) / 255
      }
    }
    return Self(
      x: Int(left), y: Int(bottom), width: width, height: height, pixels: pixels,
      radius: radius, measurement: measurement)
  }

  func value(_ values: [Float], x worldX: Int, y worldY: Int, outside: Float = 0) -> Float {
    let column = worldX - x
    let row = worldY - y
    guard column >= 0, row >= 0, column < width, row < height else { return outside }
    return values[row * width + column]
  }

  func difference(from other: Self) throws -> (geometry: Double, appearance: Double) {
    if x == other.x, y == other.y, width == other.width, height == other.height,
      radius == other.radius, pixels == other.pixels
    {
      return (0, 0)
    }
    var geometry = 0.0
    var band = 0.0
    var differences = [Double](repeating: 0, count: 3)
    var unions = differences
    let leftChannels = [pixels] + blurred
    let rightChannels = [other.pixels] + other.blurred
    let radius = max(radius, other.radius)
    for row in min(y, other.y)..<max(y + height, other.y + other.height) {
      try Task.checkCancellation()
      for column in min(x, other.x)..<max(x + width, other.x + other.width) {
        let a = value(field, x: column, y: row, outside: radius)
        let b = other.value(other.field, x: column, y: row, outside: radius)
        if abs(a) < radius || abs(b) < radius {
          geometry += Double(abs(a - b) / (2 * radius))
          band += 1
        }
        for channel in 0..<3 {
          let l = value(leftChannels[channel], x: column, y: row)
          let r = other.value(rightChannels[channel], x: column, y: row)
          differences[channel] += Double(abs(l - r))
          unions[channel] += Double(max(l, r))
        }
      }
    }
    let appearance = zip(differences, unions).map { $1 == 0 ? 0 : $0 / $1 }.reduce(0, +) / 3
    return (band == 0 ? 0 : geometry / band, appearance)
  }

  static func signedField(_ pixels: [Float], width: Int, height: Int, radius: Float) -> [Float] {
    let ink = distanceTransform(pixels.map { $0 >= 0.5 }, width: width, height: height)
    let background = distanceTransform(pixels.map { $0 < 0.5 }, width: width, height: height)
    return pixels.indices.map {
      pixels[$0] >= 0.5 ? -min(radius, sqrt(background[$0])) : min(radius, sqrt(ink[$0]))
    }
  }

  /// Separable squared Euclidean distance transform, using a lower envelope of parabolas.
  static func distanceTransform(_ sites: [Bool], width: Int, height: Int) -> [Float] {
    var result = sites.map { $0 ? Float(0) : Float(1e12) }
    for row in 0..<height {
      let offset = row * width
      let line = transform(Array(result[offset..<(offset + width)]))
      result.replaceSubrange(offset..<(offset + width), with: line)
    }
    for column in 0..<width {
      let line = transform((0..<height).map { result[$0 * width + column] })
      for row in 0..<height { result[row * width + column] = line[row] }
    }
    return result
  }

  private static func transform(_ values: [Float]) -> [Float] {
    var vertices = [Int](repeating: 0, count: values.count)
    var boundaries = [Double](repeating: .infinity, count: values.count + 1)
    boundaries[0] = -.infinity
    var k = 0
    for q in 1..<values.count {
      func crossing(_ p: Int) -> Double {
        (Double(values[q]) + Double(q * q) - Double(values[p]) - Double(p * p))
          / Double(2 * (q - p))
      }
      var intersection = crossing(vertices[k])
      while intersection <= boundaries[k] {
        k -= 1
        intersection = crossing(vertices[k])
      }
      k += 1
      vertices[k] = q
      boundaries[k] = intersection
      boundaries[k + 1] = .infinity
    }
    k = 0
    return values.indices.map { q in
      while boundaries[k + 1] < Double(q) { k += 1 }
      let delta = q - vertices[k]
      return Float(delta * delta) + values[vertices[k]]
    }
  }

  static func blur(_ values: [Float], width: Int, height: Int, sigma: Double) -> [Float] {
    let radius = Int(ceil(3 * sigma))
    var kernel = (-radius...radius).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
    let sum = kernel.reduce(0, +)
    kernel = kernel.map { $0 / sum }
    var horizontal = values
    var result = values
    // Each signal has zero padding at both ends; convolution therefore preserves
    // the same boundary condition as the raster's transparent background.
    var row = [Float](repeating: 0, count: width + radius * 2)
    var column = [Float](repeating: 0, count: height + radius * 2)
    kernel.withUnsafeBufferPointer { filter in
      for y in 0..<height {
        row.replaceSubrange(
          radius..<(radius + width), with: values[(y * width)..<((y + 1) * width)])
        row.withUnsafeBufferPointer { source in
          horizontal.withUnsafeMutableBufferPointer { destination in
            vDSP_conv(
              source.baseAddress!, 1, filter.baseAddress!, 1,
              destination.baseAddress! + y * width, 1, vDSP_Length(width), vDSP_Length(kernel.count)
            )
          }
        }
      }
      for x in 0..<width {
        for y in 0..<height { column[radius + y] = horizontal[y * width + x] }
        column.withUnsafeBufferPointer { source in
          result.withUnsafeMutableBufferPointer { destination in
            vDSP_conv(
              source.baseAddress!, 1, filter.baseAddress!, 1,
              destination.baseAddress! + x, vDSP_Stride(width), vDSP_Length(height),
              vDSP_Length(kernel.count))
          }
        }
      }
    }
    return result
  }
}
