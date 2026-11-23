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

import SwiftUI

struct Content: View {
  @State private var size = 22.0

  var body: some View {
    VStack {
      Text("Tab picker repro")
      Slider(value: $size, in: 10...144).accessibilityIdentifier("Size")
    }.padding().frame(minWidth: 1080, minHeight: 680)
  }
}

@main
struct TabPickerRepro: App {
  var body: some Scene {
    WindowGroup("Tab picker repro") {
      if CommandLine.arguments.contains("--native-appearance") {
        Content()
      } else {
        Content().preferredColorScheme(.dark)
      }
    }.restorationBehavior(.disabled).defaultSize(width: 1440, height: 900)
  }
}
