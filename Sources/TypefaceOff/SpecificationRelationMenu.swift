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
