//
//  ApplePhotosEditor.swift
//  iLightCraft
//

import CryptoKit
import Foundation
@preconcurrency import Photos
import UniformTypeIdentifiers

/// PhotoKit content editing owns same-item saves. Cached source revisions make concurrent edits explicit.
@MainActor
enum ApplePhotosEditor {

    private static func directory(_ identifier: String) throws -> URL {
        let key = SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = URL.applicationSupportDirectory.appending(path: "PhotosEditing/\(key)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func contentInput(for asset: PHAsset) async throws -> PHContentEditingInput {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        options.canHandleAdjustmentData = { @Sendable adjustment in
            PhotosAdjustment.canRead(adjustment.formatIdentifier)
                && adjustment.formatVersion == PhotosAdjustment.formatVersion
                && (try? PhotosAdjustment.decode(adjustment.data)) != nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { result, info in
                if let result { continuation.resume(returning: result) }
                else {
                    continuation.resume(throwing: (info[PHContentEditingInputErrorKey] as? Error)
                        ?? PhotoLibraryError.fileOperationFailed("Photos could not download the full-resolution image. Check access and iCloud connectivity."))
                }
            }
        }
    }

    private static func revision(_ asset: PHAsset, adjustment: PHAdjustmentData?) -> String {
        let data = adjustment?.data ?? Data()
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(asset.modificationDate?.timeIntervalSince1970 ?? -1)|\(asset.pixelWidth)x\(asset.pixelHeight)|\(adjustment?.formatIdentifier ?? "")|\(adjustment?.formatVersion ?? "")|\(hash)"
    }

    static func prepare(identifier: String) async throws -> URL {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            throw PhotoLibraryError.photoUnavailable
        }
        guard asset.mediaType == .image, !asset.mediaSubtypes.contains(.photoLive),
              asset.pixelWidth > 0, asset.pixelHeight > 0,
              asset.pixelWidth <= 80_000_000 / asset.pixelHeight else {
            throw PhotoLibraryError.fileOperationFailed("Choose a still photo up to 80 megapixels. Live Photos and video are not supported in same-item editing.")
        }
        let input = try await contentInput(for: asset)
        guard PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject?.modificationDate == asset.modificationDate else {
            throw PhotoLibraryError.externalChange
        }
        let currentRevision = revision(asset, adjustment: input.adjustmentData)
        let folder = try directory(identifier)
        let record = folder.appending(path: "current.json")
        if FileManager.default.fileExists(atPath: record.path) {
            let previous = try JSONDecoder().decode(PhotoEditContext.self, from: Data(contentsOf: record))
            guard previous.sourceFile == URL(filePath: previous.sourceFile).lastPathComponent,
                  ![".", ".."].contains(previous.sourceFile) else { throw PhotoLibraryError.invalidAdjustment }
            guard previous.revision == currentRevision else { throw PhotoLibraryError.externalChange }
            let source = folder.appending(path: previous.sourceFile)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw PhotoLibraryError.fileOperationFailed("The Photos working source is missing. Reload its latest version using conflict recovery.")
            }
            try JSONEncoder().encode(previous).write(to: source.appendingPathExtension("photos.json"), options: .atomic)
            return source
        }
        var adjustment: PhotosAdjustment?
        if let prior = input.adjustmentData, PhotosAdjustment.canRead(prior.formatIdentifier) {
            guard prior.formatVersion == PhotosAdjustment.formatVersion else { throw PhotoLibraryError.invalidAdjustment }
            adjustment = try PhotosAdjustment.decode(prior.data)
        }
        guard let inputURL = input.fullSizeImageURL else { throw PhotoLibraryError.noImageRepresentation }
        let raw = PHAssetResource.assetResources(for: asset).first {
            ($0.type == .photo || $0.type == .alternatePhoto) && NativeImagePipeline.isRAW(fileName: $0.originalFilename, typeIdentifier: $0.uniformTypeIdentifier)
        }
        let useRAW = raw != nil && (input.adjustmentData == nil || adjustment?.rawDecoderVersion != nil)
        let suffix = useRAW ? (URL(filePath: raw?.originalFilename ?? "photo.dng").pathExtension) : inputURL.pathExtension
        let source = folder.appending(path: UUID().uuidString).appendingPathExtension(suffix.isEmpty ? "image" : suffix)
        if useRAW, let raw {
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: raw, toFile: source, options: options) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        } else {
            try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: inputURL, to: source) }.value
        }
        var context = PhotoEditContext(assetIdentifier: identifier, revision: currentRevision,
                                      sourceFile: source.lastPathComponent, initialSettings: adjustment?.settings,
                                      rawDecoderVersion: adjustment?.rawDecoderVersion)
        context.sourceIsRAW = useRAW
        context.displayName = PHAssetResource.assetResources(for: asset).first { $0.type == .photo }?.originalFilename
            ?? inputURL.lastPathComponent
        let data = try JSONEncoder().encode(context)
        try data.write(to: source.appendingPathExtension("photos.json"), options: .atomic)
        try data.write(to: record, options: .atomic)
        return source
    }

    /// Archives only the association. Original resources and engine-owned drafts remain available.
    static func archiveWorkingVersion(identifier: String) throws {
        let folder = try directory(identifier)
        let current = folder.appending(path: "current.json")
        if FileManager.default.fileExists(atPath: current.path) {
            try FileManager.default.moveItem(at: current, to: folder.appending(path: "archived-\(UUID()).json"))
        }
    }

    static func save(context: PhotoEditContext, rendered: URL, settings: Data, hdr: Bool) async throws -> (PhotoEditContext, String?) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [context.assetIdentifier], options: nil).firstObject else {
            throw PhotoLibraryError.photoUnavailable
        }
        let editingInput = try await contentInput(for: asset)
        guard revision(asset, adjustment: editingInput.adjustmentData) == context.revision else { throw PhotoLibraryError.externalChange }
        let output = PHContentEditingOutput(contentEditingInput: editingInput)
        if hdr {
            guard output.supportedRenderedContentTypes.contains(.heic) else {
                throw PhotoLibraryError.fileOperationFailed("Photos cannot accept HDR HEIC for this item; no SDR replacement was saved.")
            }
            let target = try output.renderedContentURL(for: .heic)
            try await Task.detached(priority: .userInitiated) { try NativeImagePipeline.encodeHDR(source: rendered, destination: target) }.value
        } else {
            try FileManager.default.copyItem(at: rendered, to: output.renderedContentURL)
        }
        let payload = try PhotosAdjustment(settings: settings, rawDecoderVersion: context.rawDecoderVersion)
        output.adjustmentData = PHAdjustmentData(formatIdentifier: PhotosAdjustment.identifier,
                                                formatVersion: PhotosAdjustment.formatVersion,
                                                data: try JSONEncoder().encode(payload))
        guard let latest = PHAsset.fetchAssets(withLocalIdentifiers: [context.assetIdentifier], options: nil).firstObject,
              latest.modificationDate == asset.modificationDate else { throw PhotoLibraryError.externalChange }
        // PhotoKit invokes this on its transaction queue, never on the main actor.
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest(for: latest).contentEditingOutput = output
        }

        var saved = context
        let current = PHAsset.fetchAssets(withLocalIdentifiers: [context.assetIdentifier], options: nil).firstObject
        if let current { saved.revision = revision(current, adjustment: output.adjustmentData) }
        saved.initialSettings = settings
        do {
            if let current {
                let confirmed = try await contentInput(for: current)
                saved.revision = revision(current, adjustment: confirmed.adjustmentData)
            }
            let folder = try directory(context.assetIdentifier)
            let bytes = try JSONEncoder().encode(saved)
            try bytes.write(to: folder.appending(path: "current.json"), options: .atomic)
            try bytes.write(to: folder.appending(path: saved.sourceFile).appendingPathExtension("photos.json"), options: .atomic)
            return (saved, nil)
        } catch {
            return (saved, "The edit was saved in Photos, but the local cache record could not be updated. Keep this editing copy for recovery.")
        }
    }
}
