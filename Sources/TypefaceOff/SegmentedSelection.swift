import SwiftUI

extension Binding where Value: Sendable {
  /// An accessibility press on a segmented picker sets its selection during a view update, where
  /// publishing an observable object's change is undefined, so the change waits for the update.
  @MainActor var settingAfterViewUpdate: Binding<Value> {
    Binding(get: { wrappedValue }, set: { value in Task { @MainActor in wrappedValue = value } })
  }
}
