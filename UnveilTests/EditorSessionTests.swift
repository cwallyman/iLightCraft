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
    func adjustToolRequiresPhotoAndRetainsGroup() async {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let session = EditorSession(viewModel: model, libraryLoader: ControlledPhotoLibraryLoader())

        session.showPanel(.color)
        #expect(!session.isCardOpen)

        await model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        session.showPanel(.color)
        #expect(session.isCardOpen)
        #expect(session.selectedGroup == .color)

        session.select(.move)
        #expect(!session.isCardOpen)
        session.select(.adjust)
        #expect(session.isCardOpen)
        #expect(session.selectedGroup == .color)
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
        #expect(session.isImporting)

        let selected = URL(filePath: "/tmp/staged.RAF")
        loader.complete(.success(selected))
        await task.value

        #expect(loader.discardedURLs == [selected])
        #expect(model.openPhoto == previous)
        #expect(!session.isImporting)
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

        #expect(!session.isImporting)
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
    func successfulOpenPresentsEditor() async throws {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let loader = ControlledPhotoLibraryLoader()
        let session = EditorSession(viewModel: model, libraryLoader: loader)
        #expect(!session.isEditorPresented)

        await session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        #expect(session.isEditorPresented)
        #expect(model.isPhotoOpen)

        session.goHome()
        let task = Task { await session.importLibraryPhoto(from: NSItemProvider()) }
        try await waitUntil(seconds: 3) { loader.loadCount == 1 }
        loader.complete(.success(URL(filePath: "/tmp/library.RAF")))
        await task.value
        #expect(session.isEditorPresented)
    }

    /// failedOpenStaysHome covers both paths: an engine failure on a Files pick and a Photos
    /// selection that never yields a file. Each leaves the home up with its alert.
    @Test
    func failedOpenStaysHome() async throws {
        let engine = FakeEngine()
        let model = EditorViewModel(
            engine        : engine,
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let loader = ControlledPhotoLibraryLoader()
        let session = EditorSession(viewModel: model, libraryLoader: loader)
        engine.failNextOpen = .engine("Open failed")

        await session.open(pickedURL: URL(filePath: "/tmp/broken.RAF"))
        #expect(!session.isEditorPresented)
        #expect(session.presentedAlert?.message == "Open failed")
        session.dismissAlert()

        let task = Task { await session.importLibraryPhoto(from: NSItemProvider()) }
        try await waitUntil(seconds: 3) { loader.loadCount == 1 }
        loader.complete(.failure(.noImageRepresentation))
        await task.value
        #expect(!session.isEditorPresented)
        #expect(session.presentedAlert?.title == "Unable to Open Photo")
    }

    /// suspendedFirstPreviewStillPresentsEditor covers an app that left while the photo opened: the
    /// engine refused the first preview, yet the open stands with no alert and the resume refresh draws it.
    @Test
    func suspendedFirstPreviewStillPresentsEditor() async {
        let engine = FakeEngine()
        let model = EditorViewModel(
            engine        : engine,
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let session = EditorSession(viewModel: model, libraryLoader: ControlledPhotoLibraryLoader())
        engine.failNextPreview = .suspended("the session is suspended")

        await session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        #expect(session.isEditorPresented)
        #expect(model.openPhoto == PhotoID(rawValue: 1))
        #expect(session.presentedAlert == nil)

        await model.refreshPreview()
        #expect(engine.calls == ["open /tmp/photo.RAF", "preview 64 full", "preview 64 full"])
    }

    /// failedFirstPreviewAlertsInEditor covers any other refusal of the first preview: the open still
    /// stands, and its alert shows over the editor instead of sending the user home.
    @Test
    func failedFirstPreviewAlertsInEditor() async {
        let engine = FakeEngine()
        let model = EditorViewModel(
            engine        : engine,
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let session = EditorSession(viewModel: model, libraryLoader: ControlledPhotoLibraryLoader())
        engine.failNextPreview = .engine("Render failed")

        await session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        #expect(session.isEditorPresented)
        #expect(model.openPhoto == PhotoID(rawValue: 1))
        #expect(session.presentedAlert?.message == "Render failed")
    }

    @Test
    func goingHomeKeepsPhotoAndValues() async {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let session = EditorSession(viewModel: model, libraryLoader: ControlledPhotoLibraryLoader())
        await session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        await model.drag(.exposure, to: 1)
        await model.endDrag(.exposure)
        session.showPanel(.light)
        let photo = model.openPhoto

        session.goHome()
        #expect(!session.isEditorPresented)
        #expect(!session.isCardOpen)
        #expect(model.openPhoto == photo)
        #expect(model.values[.exposure] == 1)
    }

    @Test
    func pickWhileImportingIsIgnored() async throws {
        let engine = FakeEngine()
        let model = EditorViewModel(
            engine        : engine,
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let loader = ControlledPhotoLibraryLoader()
        let session = EditorSession(viewModel: model, libraryLoader: loader)
        let task = Task { await session.importLibraryPhoto(from: NSItemProvider()) }
        try await waitUntil(seconds: 3) { loader.loadCount == 1 }

        await session.open(pickedURL: URL(filePath: "/tmp/second.RAF"))
        await session.importLibraryPhoto(from: NSItemProvider())
        #expect(engine.calls.isEmpty)
        #expect(loader.loadCount == 1)
        #expect(session.isImporting)

        loader.complete(.success(URL(filePath: "/tmp/first.RAF")))
        await task.value
        #expect(engine.calls.first == "open /tmp/first.RAF")
        #expect(session.isEditorPresented)
        #expect(!session.isImporting)
    }

    /// A Photos pick is titled with the picker file's name, or "Photo" for a generated identifier.
    @Test(arguments: [("IMG_0042.HEIC", "IMG_0042"), ("\(UUID().uuidString).JPG", "Photo")])
    func photosPickIsTitledByAMeaningfulFileName(name: String, title: String) async throws {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 64
        )
        let loader  = ControlledPhotoLibraryLoader()
        let session = EditorSession(viewModel: model, libraryLoader: loader)
        let task    = Task { await session.importLibraryPhoto(from: NSItemProvider()) }
        try await waitUntil(seconds: 3) { loader.loadCount == 1 }

        loader.complete(.success(URL(filePath: "/tmp/\(name)")))
        await task.value

        #expect(model.photoTitle == title)
    }
}
