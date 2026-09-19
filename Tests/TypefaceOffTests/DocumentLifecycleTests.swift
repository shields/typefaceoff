import AppKit
import Testing
import TypefaceCore

@testable import TypefaceOff

@Suite(.serialized) @MainActor struct DocumentLifecycleTests {
  @Test func documentsOpenSaveAndRejectInvalidFiles() async throws {
    #expect(WorkbenchDocument.readableContentTypes == [.typefaceComparison])
    let controller = NSDocumentController.shared
    let newDocument = try controller.openUntitledDocumentAndDisplay(true)
    defer { newDocument.close() }
    #expect(!newDocument.windowControllers.isEmpty)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let destination = folder.appendingPathComponent("new.typefaceoff")
    try await newDocument.save(
      to: destination, ofType: "com.shields.typefaceoff.comparison", for: .saveAsOperation)
    #expect(try Comparison.decode(Data(contentsOf: destination)) == Comparison())

    var saved = Comparison()
    saved.a.size = 36
    saved.sample = .custom
    saved.customText = "A saved comparison"
    let source = folder.appendingPathComponent("saved.typefaceoff")
    try saved.encoded().write(to: source)
    let (opened, alreadyOpen) = try await controller.openDocument(
      withContentsOf: source, display: true)
    defer { opened.close() }
    #expect(!alreadyOpen)
    let copy = folder.appendingPathComponent("copy.typefaceoff")
    try await opened.save(
      to: copy, ofType: "com.shields.typefaceoff.comparison", for: .saveAsOperation)
    #expect(try Comparison.decode(Data(contentsOf: copy)) == saved)

    let invalid = folder.appendingPathComponent("invalid.typefaceoff")
    try Data("invalid".utf8).write(to: invalid)
    await #expect(throws: (any Error).self) {
      _ = try await controller.openDocument(withContentsOf: invalid, display: false)
    }
    let directory = folder.appendingPathComponent("directory.typefaceoff")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    await #expect(throws: (any Error).self) {
      _ = try await controller.openDocument(withContentsOf: directory, display: false)
    }
  }
}
