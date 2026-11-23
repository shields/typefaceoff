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
import TypefaceCore

struct SpecificationRelationMenu: View {
  @ObservedObject var model: WorkbenchModel
  let setting: SpecificationSetting
  let identifier: String
  @Environment(\.workbenchUndoManager) private var undoManager
  @Environment(\.locale) private var locale

  var body: some View {
    if let relation = setting.relation(in: model.comparison, locale: locale) {
      Menu(relation) {
        Button("Make B Equal to A") { equalize(from: .a) }
        Button("Make A Equal to B") { equalize(from: .b) }
      }.menuStyle(.borderlessButton).fixedSize()
        .accessibilityIdentifier("\(identifier) \(setting) relation")
        .accessibilityValue(
          setting == .size ? "B is \(relation.dropFirst()) times A" : "B is A \(relation)")
    }
  }

  private func equalize(from side: Side) {
    let config = model.comparison[side]!
    let entry: SpecificationValue.Entry =
      setting == .leading && config.leading == nil ? .automatic : .number(setting.value(in: config))
    model.edit("Equalize appearance", undoManager: undoManager) {
      setting.apply(entry, to: &$0, side: side, both: true, catalog: model.catalog)
    }
  }
}
