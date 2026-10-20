//
//  PhotosAdjustmentTests.swift
//  UnveilTests
//

import Foundation
import Testing
import CoreImage
import Synchronization
@preconcurrency import Photos
@testable import Unveil

struct PhotosAdjustmentTests {

    /// Opt-in regression: PhotoKit must invoke the save callback without a main-actor trap.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UNVEIL_RUN_PHOTOS_SAVE_REGRESSION"] == "1"))
    @MainActor
    func saveSyntheticPhotoOnPhotosTransactionQueue() async throws {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            Issue.record("Grant the test host Photos read/write access before this opt-in check.")
            return
        }
        let folder = URL.temporaryDirectory.appending(path: "photos-save-regression-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "synthetic.jpg")
        let image = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            Issue.record("sRGB unavailable")
            return
        }
        try CIContext().writeJPEGRepresentation(of: image, to: source, colorSpace: space, options: [:])
        let created = Mutex<String?>(nil)
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: source)
            created.withLock { $0 = request?.placeholderForCreatedAsset?.localIdentifier }
        }
        guard let identifier = created.withLock({ $0 }),
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            Issue.record("Could not create the disposable synthetic asset")
            return
        }
        do {
            let working = try await ApplePhotosEditor.prepare(identifier: identifier)
            guard let context = try PhotoEditContext.read(for: working) else {
                throw PhotoLibraryError.invalidAdjustment
            }
            let settings = Data(#"{"version":1,"light":{"exposure":0.5}}"#.utf8)
            let saved = try await ApplePhotosEditor.save(context: context, rendered: source, settings: settings, hdr: false)
            #expect(saved.0.assetIdentifier == identifier)
            #expect(saved.0.initialSettings == settings)
            #expect(saved.0.revision != context.revision)
        } catch {
            try? await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }
            throw error
        }
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }

    @Test
    func completeSettingsRemainOpaqueAndRoundTrip() throws {
        let settings = Data(#"{"version":1,"light":{"exposure":0.75},"hdr":{"enabled":true},"future":{"keep":[1,2,3]}}"#.utf8)
        let payload = try PhotosAdjustment(settings: settings, rawDecoderVersion: "saved-decoder")
        let reopened = try PhotosAdjustment.decode(JSONEncoder().encode(payload))
        #expect(reopened.settings == settings)
        #expect(reopened.rawDecoderVersion == "saved-decoder")
    }

    @Test
    func unsupportedSettingsAndEnvelopeAreRejected() throws {
        #expect(throws: (any Error).self) {
            try PhotosAdjustment(settings: Data(#"{"version":99}"#.utf8), rawDecoderVersion: nil)
        }
        #expect(throws: (any Error).self) {
            try PhotosAdjustment.decode(Data(#"{"schema":99,"engine":"future","settings":"e30="}"#.utf8))
        }
    }
}
