import Accelerate
import CoreGraphics
import Foundation

enum GlyphOverlay {
  static func draw(
    _ a: [UInt8], _ b: [UInt8], width: Int, height: Int, context: CGContext, rect: CGRect
  ) {
    let pixels = pixels(a, b)
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { return }
    context.draw(image, in: rect)
  }

  /// Composite coverage masks using vector operations, including in unoptimized app builds.
  static func pixels(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
    precondition(!a.isEmpty && a.count == b.count)
    let count = vDSP_Length(a.count)
    var left = [Float](repeating: 0, count: a.count)
    var right = [Float](repeating: 0, count: a.count)
    vDSP_vfltu8(a, 1, &left, 1, count)
    vDSP_vfltu8(b, 1, &right, 1, count)
    var shared = [Float](repeating: 0, count: a.count)
    vDSP_vmin(left, 1, right, 1, &shared, 1, count)
    var channel = [Float](repeating: 0, count: a.count)
    var planes = [UInt8](repeating: 0, count: a.count * 4)
    channel.withUnsafeMutableBufferPointer { values in
      planes.withUnsafeMutableBufferPointer { output in
        let palette: [(Float, Float, Float)] = [
          (180 / 255, 40 / 255, 27 / 255), (59 / 255, 107 / 255, 28 / 255),
          (67 / 255, 157 / 255, 31 / 255),
        ]
        for (index, colors) in palette.enumerated() {
          var (red, blue, ink) = colors
          var overlap: Float = ink - red - blue
          // a * red + b * blue + min(a, b) * (black - red - blue)
          vDSP_vsmsma(left, 1, &red, right, 1, &blue, values.baseAddress!, 1, count)
          vDSP_vsma(shared, 1, &overlap, values.baseAddress!, 1, values.baseAddress!, 1, count)
          vDSP_vfixru8(values.baseAddress!, 1, output.baseAddress! + index * a.count, 1, count)
        }
        vDSP_vmax(left, 1, right, 1, values.baseAddress!, 1, count)
        vDSP_vfixu8(values.baseAddress!, 1, output.baseAddress! + 3 * a.count, 1, count)
      }
    }
    var pixels = [UInt8](repeating: 0, count: a.count * 4)
    planes.withUnsafeMutableBytes { input in
      pixels.withUnsafeMutableBytes { output in
        var red = vImage_Buffer(
          data: input.baseAddress!, height: 1, width: count, rowBytes: a.count)
        var green = vImage_Buffer(
          data: input.baseAddress! + a.count, height: 1, width: count, rowBytes: a.count)
        var blue = vImage_Buffer(
          data: input.baseAddress! + a.count * 2, height: 1, width: count, rowBytes: a.count)
        var alpha = vImage_Buffer(
          data: input.baseAddress! + a.count * 3, height: 1, width: count, rowBytes: a.count)
        var rgba = vImage_Buffer(
          data: output.baseAddress!, height: 1, width: count, rowBytes: a.count * 4)
        // The interleaver copies channels in argument order; the resulting image uses RGBA.
        _ = vImageConvert_Planar8toARGB8888(
          &red, &green, &blue, &alpha, &rgba, vImage_Flags(kvImageNoFlags))
      }
    }
    return pixels
  }
}
