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

import Accelerate
import AppKit
import CoreGraphics
import Foundation

enum GlyphOverlay {
  static func draw(
    _ a: [UInt8], _ b: [UInt8], width: Int, height: Int, context: CGContext, rect: CGRect,
    differentiateWithoutColor: Bool = false, scale: CGFloat = 1
  ) {
    let pixels = pixels(
      a, b, increasedContrast: WorkbenchStyle.increasedContrast(.currentDrawing()))
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { return }
    context.draw(image, in: rect)
    if differentiateWithoutColor {
      for (left, right, rising) in [(a, b, true), (b, a, false)] {
        let coverage = zip(left, right).map { $0 > $1 ? $0 - $1 : 0 }
        let provider = CGDataProvider(data: Data(coverage) as CFData)!
        let mask = CGImage(
          width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
          decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        context.saveGState()
        context.setBlendMode(.sourceAtop)
        context.clip(to: rect, mask: mask)
        ComparisonHatch(rising: rising, scale: scale).draw(in: context, rect: rect)
        context.restoreGState()
      }
    }
  }

  /// Composite coverage masks using vector operations, including in unoptimized app builds.
  static func pixels(_ a: [UInt8], _ b: [UInt8], increasedContrast: Bool = false) -> [UInt8] {
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
        let palette: [(Float, Float, Float)] =
          increasedContrast
          ? [(143, 26, 27), (37, 82, 28), (48, 125, 31)]
          : [(180, 40, 27), (59, 107, 28), (67, 157, 31)]
        for (index, colors) in palette.enumerated() {
          var red = colors.0 / 255
          var blue = colors.1 / 255
          let ink = colors.2 / 255
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
