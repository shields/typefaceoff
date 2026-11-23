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
