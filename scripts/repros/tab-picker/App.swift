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
