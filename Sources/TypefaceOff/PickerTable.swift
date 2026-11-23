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

import AppKit

final class PickerTableView: NSTableView {
  var confirm: (() -> Void)?
  var cancel: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36: confirm!()
    case 53: cancel!()
    default: super.keyDown(with: event)
    }
  }
}

final class PickerSelectionRow: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
  }
}
