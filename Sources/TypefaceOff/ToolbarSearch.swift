import AppKit
import SwiftUI
import TypefaceCore

struct ToolbarSearch: NSViewRepresentable {
  let comparison: Comparison
  @ObservedObject var languages: LanguageBrowserModel
  @Binding var focus: Bool
  let choose: (String) -> Void
  var load: CharacterSearchModel.Load = CharacterSearch.results

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.delegate = context.coordinator
    field.controlSize = .regular
    context.coordinator.field = field
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    coordinator.updateResults(accessibilityEnabled: context.environment.accessibilityEnabled)
    let isLanguages = comparison.mode == .languages
    field.placeholderString = isLanguages ? "Search Languages" : "Find Character"
    field.setAccessibilityLabel(field.placeholderString)
    let query = isLanguages ? languages.filter.query : coordinator.session.query
    if !field.stringValue.unicodeScalars.elementsEqual(query.unicodeScalars) {
      field.stringValue = query
    }
    if isLanguages {
      coordinator.popover.close()
    } else {
      Task { @MainActor [weak coordinator] in
        if let coordinator, coordinator.field?.delegate === coordinator {
          coordinator.session.configure(coordinator.parent.comparison)
        }
      }
    }
    if focus {
      Task { @MainActor in
        field.window?.makeFirstResponder(field)
        coordinator.parent.focus = false
      }
    }
  }

  static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
    coordinator.popover.close()
    coordinator.session.cancel()
    field.delegate = nil
  }

  @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate, NSPopoverDelegate {
    var parent: ToolbarSearch
    weak var field: NSSearchField?
    let session: ToolbarSearchSession
    let popover = NSPopover()
    private let results = NSHostingController(rootView: AnyView(EmptyView()))

    init(_ parent: ToolbarSearch) {
      self.parent = parent
      session = ToolbarSearchSession(load: parent.load)
      super.init()
      popover.delegate = self
      popover.behavior = .transient
      popover.animates = false
      popover.contentViewController = results
      session.choose = { [weak self] in self?.choose($0) }
    }

    func updateResults(accessibilityEnabled: Bool) {
      results.rootView = AnyView(
        ToolbarSearchResults(session: session) { [weak self] in self?.choose($0) }
          .environment(\.accessibilityEnabled, accessibilityEnabled))
    }

    func popoverDidClose(_ notification: Notification) { session.cancel() }

    func controlTextDidBeginEditing(_ notification: Notification) { showResults() }

    func controlTextDidChange(_ notification: Notification) {
      guard let field else { return }
      if parent.comparison.mode == .languages {
        parent.languages.filter.query = field.stringValue
      } else {
        session.search(field.stringValue)
        showResults()
      }
    }

    func control(
      _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
    ) -> Bool {
      guard !textView.hasMarkedText() else { return false }
      if selector == #selector(NSResponder.cancelOperation(_:)) {
        popover.close()
        field?.window?.makeFirstResponder(nil)
        return true
      }
      guard parent.comparison.mode != .languages else { return false }
      switch selector {
      case #selector(NSResponder.moveDown(_:)): session.move(1)
      case #selector(NSResponder.moveUp(_:)): session.move(-1)
      case #selector(NSResponder.insertNewline(_:)): session.confirm()
      default: return false
      }
      return true
    }

    private func showResults() {
      guard parent.comparison.mode != .languages, let field, !popover.isShown else { return }
      session.resume()
      popover.show(relativeTo: field.bounds, of: field, preferredEdge: .minY)
      field.window?.makeFirstResponder(field)
    }

    private func choose(_ glyph: String) {
      popover.close()
      field?.window?.makeFirstResponder(nil)
      parent.choose(glyph)
    }
  }
}

@MainActor final class ToolbarSearchSession: ObservableObject {
  @Published private(set) var query = ""
  @Published private(set) var answer: CharacterSearchModel.Answer?
  @Published var selection: [Unicode.Scalar]?
  @Published private(set) var comparison = Comparison()
  var choose: (String) -> Void = { _ in }
  private let search: CharacterSearchModel
  private var task: Task<Void, Never>?
  private var confirming: CharacterSearchModel.Request?

  init(load: @escaping CharacterSearchModel.Load) {
    search = CharacterSearchModel(load: load)
  }

  var request: CharacterSearchModel.Request {
    .init(query: query, fonts: [comparison.a, comparison.b].compactMap { $0 })
  }

  func configure(_ comparison: Comparison) {
    let previous = request
    if self.comparison != comparison { self.comparison = comparison }
    if request != previous { run() }
  }

  func search(_ query: String) {
    self.query = query
    confirming = nil
    run()
  }

  func resume() {
    if answer?.request != request && task == nil { run() }
  }

  private func run() {
    task?.cancel()
    let request = request
    task = Task {
      await search.update(request)
      guard !Task.isCancelled, self.request == request else { return }
      task = nil
      answer = search.answer
      selection = answer?.results.first?.id
      if confirming == request { confirm() }
      confirming = nil
    }
  }

  func move(_ offset: Int) {
    guard answer?.request == request, let results = answer?.results, !results.isEmpty else {
      return
    }
    let index =
      selection.flatMap { selection in results.firstIndex { $0.id == selection } }
      ?? (offset > 0 ? -1 : results.count)
    selection = results[min(max(index + offset, 0), results.count - 1)].id
  }

  func confirm() {
    guard answer?.request == request else {
      confirming = request
      return
    }
    if let result = answer?.results.first(where: { $0.id == selection }) { choose(result.glyph) }
  }

  func cancel() {
    task?.cancel()
    task = nil
    confirming = nil
  }
}

private struct ToolbarSearchResults: View {
  @ObservedObject var session: ToolbarSearchSession
  let choose: (String) -> Void

  var body: some View {
    Group {
      if session.query.isEmpty {
        Text("Search by name, character, or code point, such as left arrow, é, or U+2192.")
          .foregroundStyle(WorkbenchStyle.secondaryInk).padding(24)
      } else if let answer = session.answer, answer.request == session.request {
        if answer.results.isEmpty {
          Text("No matching characters").foregroundStyle(WorkbenchStyle.secondaryInk)
        } else {
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(spacing: 0) {
                ForEach(answer.results) { result in
                  Button {
                    choose(result.glyph)
                  } label: {
                    HStack(spacing: 8) {
                      Rectangle()
                        .fill(session.selection == result.id ? WorkbenchStyle.ink : .clear)
                        .frame(width: 2, height: 28)
                      CharacterSearchRow(
                        result: result, fonts: answer.request.fonts,
                        names: CharacterSearchRow.names(of: answer.request.fonts),
                        spacingOnly: session.comparison.spacing && !session.comparison.shape)
                    }.padding(.horizontal, 8).padding(.vertical, 4)
                  }.buttonStyle(.plain).id(result.id)
                    .accessibilityLabel(
                      CharacterSearchRow.label(
                        result, names: CharacterSearchRow.names(of: answer.request.fonts)))
                }
              }
            }.onChange(of: session.selection) { _, id in
              if let id { proxy.scrollTo(id) }
            }
          }
        }
      } else {
        ProgressView().controlSize(.small).accessibilityLabel("Searching characters")
      }
    }.frame(width: 440, height: 400).background(WorkbenchStyle.paper).preferredColorScheme(.light)
  }
}
