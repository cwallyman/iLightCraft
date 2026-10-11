//
//  EditorSessionTests.swift
//  UnveilTests
//

import Foundation
import Testing
@testable import Unveil

@MainActor
struct EditorSessionTests {

    @Test
    func inspectorRequiresPhotoAndRetainsSelection() async {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let session = EditorSession(viewModel: model, libraryLoader: ControlledPhotoLibraryLoader())

        session.showPanel(.color)
        #expect(!session.isInspectorPresented)

        await model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        session.showPanel(.color)
        #expect(session.isInspectorPresented)
        #expect(session.inspector.selectedGroup == .color)

        session.isInspectorPresented = false
        session.toggleInspector()
        #expect(session.isInspectorPresented)
        #expect(session.inspector.selectedGroup == .color)
    }

    /// failedOpenReleasesStagingAndKeepsPhoto verifies that moving import ownership out of the
    /// view controller does not discard the displayed photo or leak the Photos selection.
    @Test
    func failedOpenReleasesStagingAndKeepsPhoto() async throws {
        let engine = FakeEngine()
        let model = EditorViewModel(
            engine        : engine,
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let loader = ControlledPhotoLibraryLoader()
        let session = EditorSession(viewModel: model, libraryLoader: loader)
        await model.open(pickedURL: URL(filePath: "/tmp/previous.RAF"))
        let previous = model.openPhoto
        engine.failNextOpen = .engine("Open failed")

        let task = Task { await session.importLibraryPhoto(from: NSItemProvider()) }
        try await waitUntil(seconds: 3) { loader.loadCount == 1 }
        #expect(session.isImportingFromLibrary)

        let selected = URL(filePath: "/tmp/staged.RAF")
        loader.complete(.success(selected))
        await task.value

        #expect(loader.discardedURLs == [selected])
        #expect(model.openPhoto == previous)
        #expect(!session.isImportingFromLibrary)
        #expect(session.presentedAlert?.message == "Open failed")
        session.dismissAlert()
        #expect(model.errorMessage == nil)
    }

    @Test
    func loadingRejectsConcurrentSelectionAndRecoversAfterFailure() async throws {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let loader = ControlledPhotoLibraryLoader()
        let session = EditorSession(viewModel: model, libraryLoader: loader)
        let task = Task { await session.importLibraryPhoto(from: NSItemProvider()) }
        try await waitUntil(seconds: 3) { loader.loadCount == 1 }

        await session.importLibraryPhoto(from: NSItemProvider())
        #expect(loader.loadCount == 1)
        loader.complete(.failure(.noImageRepresentation))
        await task.value

        #expect(!session.isImportingFromLibrary)
        #expect(loader.discardedURLs.isEmpty)
        #expect(session.presentedAlert?.title == "Unable to Open Photo")
        session.dismissAlert()
        #expect(session.presentedAlert == nil)

        let retry = Task { await session.importLibraryPhoto(from: NSItemProvider()) }
        try await waitUntil(seconds: 3) { loader.loadCount == 2 }
        let selected = URL(filePath: "/tmp/retry.RAF")
        loader.complete(.success(selected))
        await retry.value
        #expect(model.isPhotoOpen)
        #expect(loader.discardedURLs == [selected])
    }

    @Test
    func cancellingPhotosDoesNotImport() async {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let loader = ControlledPhotoLibraryLoader()
        let session = EditorSession(viewModel: model, libraryLoader: loader)
        session.finishPhotoSelection(nil)
        await session.importSelectedLibraryPhoto()
        #expect(loader.loadCount == 0)
        #expect(!session.isPhotoPickerPresented)
        #expect(session.presentedAlert == nil)
    }
}
