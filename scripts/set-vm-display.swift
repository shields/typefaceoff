import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("set-vm-display: \(message)\n".utf8))
  exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let width = Int(arguments[1]), let height = Int(arguments[2]) else {
  fail("usage: set-vm-display.swift WIDTH HEIGHT")
}

let display = CGMainDisplayID()
let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []
// The HiDPI mode renders at twice the point size, like a Retina Mac.
guard
  let mode = modes.first(where: {
    $0.width == width && $0.height == height && $0.pixelWidth == 2 * width
  })
else {
  fail("the display has no \(width)x\(height) HiDPI mode")
}

var configuration: CGDisplayConfigRef?
guard
  CGBeginDisplayConfiguration(&configuration) == .success,
  CGConfigureDisplayWithDisplayMode(configuration, display, mode, nil) == .success,
  CGCompleteDisplayConfiguration(configuration, .forSession) == .success
else {
  fail("could not switch the display to \(width)x\(height)")
}

guard let current = CGDisplayCopyDisplayMode(display), current.width == width,
  current.height == height
else {
  fail("the display did not switch to \(width)x\(height)")
}
