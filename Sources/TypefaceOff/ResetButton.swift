import SwiftUI

struct ResetButton: View {
  let label: String
  let action: () -> Void
  @State private var activation = false

  var body: some View {
    Button {
      activation.toggle()
      action()
    } label: {
      Image(systemName: "slider.horizontal.2.arrow.trianglehead.counterclockwise")
        .symbolEffect(.wiggle, options: .nonRepeating, value: activation)
    }.accessibilityLabel(label)
  }
}
