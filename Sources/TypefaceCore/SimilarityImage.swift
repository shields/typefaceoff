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
    blurred = Self.sigmas.map { Self.blur(pixels, width: width, height: height, sigma: $0) }
  }

  static let sigmas = [0.75, 1.5]

  /// Coverage padded for `radius`, which the signed field must then share.
  struct Raster: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let pixels: [Float]
    let radius: Float
    let measurement: GlyphMeasurement
  }

  init(_ raster: Raster) {
    self.init(
      x: raster.x, y: raster.y, width: raster.width, height: raster.height, pixels: raster.pixels,
      radius: raster.radius, measurement: raster.measurement)
  }

  static func rasterize(
    _ line: CTLine, scale: Double, radius: Float,
    makeContext: (UnsafeMutableRawPointer?, Int, Int) -> CGContext? = { data, width, height in
      CGContext(
        data: data, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder32Big.rawValue)
    }
  ) throws -> Raster {
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
      guard let context = makeContext(bytes.baseAddress, width, height)
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
    return Raster(
      x: Int(left), y: Int(bottom), width: width, height: height, pixels: pixels, radius: radius,
      measurement: measurement)
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
    let radius = max(radius, other.radius)
    let twice = 2 * radius
    let columns = min(x, other.x)..<max(x + width, other.x + other.width)
    let span = columns.count
    var geometry = 0.0
    var band = 0.0
    var differences = (0.0, 0.0, 0.0)
    var unions = (0.0, 0.0, 0.0)
    var rows = [Float](repeating: 0, count: span * 8)
    try rows.withUnsafeMutableBufferPointer { buffer in
      let left = buffer.baseAddress!
      let right = left + span * 4
      for row in min(y, other.y)..<max(y + height, other.y + other.height) {
        try Task.checkCancellation()
        fill(left, row: row, columns: columns, outside: radius)
        other.fill(right, row: row, columns: columns, outside: radius)
        for column in 0..<span {
          let a = left[column]
          let b = right[column]
          if abs(a) < radius || abs(b) < radius {
            geometry += Double(abs(a - b) / twice)
            band += 1
          }
          func add(_ channel: Int, _ difference: inout Double, _ union: inout Double) {
            let l = left[span * channel + column]
            let r = right[span * channel + column]
            difference += Double(abs(l - r))
            union += Double(max(l, r))
          }
          add(1, &differences.0, &unions.0)
          add(2, &differences.1, &unions.1)
          add(3, &differences.2, &unions.2)
        }
      }
    }
    let channels = [
      (differences.0, unions.0), (differences.1, unions.1), (differences.2, unions.2),
    ]
    let appearance = channels.map { $0.1 == 0 ? 0 : $0.0 / $0.1 }.reduce(0, +) / 3
    return (band == 0 ? 0 : geometry / band, appearance)
  }

  private func fill(
    _ destination: UnsafeMutablePointer<Float>, row: Int, columns: Range<Int>, outside: Float
  ) {
    let span = columns.count
    destination.update(repeating: outside, count: span)
    (destination + span).update(repeating: 0, count: span * 3)
    guard (y..<y + height).contains(row) else { return }
    let start = destination + x - columns.lowerBound
    let source = (row - y) * width
    func copy(_ values: [Float], channel: Int) {
      values.withUnsafeBufferPointer {
        (start + channel * span).update(from: $0.baseAddress! + source, count: width)
      }
    }
    copy(field, channel: 0)
    copy(pixels, channel: 1)
    copy(blurred[0], channel: 2)
    copy(blurred[1], channel: 3)
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
    var result = sites.map { $0 ? 0 : Float(1e12) }
    var envelope = Envelope(capacity: max(width, height))
    result.withUnsafeMutableBufferPointer { values in
      let base = values.baseAddress!
      for row in 0..<height { envelope.transform(base + row * width, count: width, stride: 1) }
      for column in 0..<width { envelope.transform(base + column, count: height, stride: width) }
    }
    return result
  }

  private struct Envelope {
    var line: [Float]
    var vertices: [Int]
    var boundaries: [Double]

    init(capacity: Int) {
      line = .init(repeating: 0, count: capacity)
      vertices = .init(repeating: 0, count: capacity)
      boundaries = .init(repeating: 0, count: capacity + 1)
    }

    mutating func transform(_ values: UnsafeMutablePointer<Float>, count: Int, stride: Int) {
      line.withUnsafeMutableBufferPointer { line in
        vertices.withUnsafeMutableBufferPointer { vertices in
          boundaries.withUnsafeMutableBufferPointer { boundaries in
            for q in 0..<count { line[q] = values[q * stride] }
            vertices[0] = 0
            boundaries[0] = -.infinity
            boundaries[1] = .infinity
            var k = 0
            for q in 1..<count {
              func crossing(_ p: Int) -> Double {
                (Double(line[q]) + Double(q * q) - Double(line[p]) - Double(p * p))
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
            for q in 0..<count {
              while boundaries[k + 1] < Double(q) { k += 1 }
              let delta = q - vertices[k]
              values[q * stride] = Float(delta * delta) + line[vertices[k]]
            }
          }
        }
      }
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
