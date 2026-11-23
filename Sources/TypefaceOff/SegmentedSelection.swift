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

extension Binding where Value: Sendable {
  /// An accessibility press on a segmented picker sets its selection during a view update, where
  /// publishing an observable object's change is undefined, so the change waits for the update.
  @MainActor var settingAfterViewUpdate: Binding<Value> {
    Binding(get: { wrappedValue }, set: { value in Task { @MainActor in wrappedValue = value } })
  }
}
