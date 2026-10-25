//
//  PhotoLibraryStore.swift
//  iLightCraft
//

import Observation
import Photos
import PhotosUI
import UIKit

/// PhotoLibraryStore is what the home's Photos panel shows of the library: the access the user
/// granted, Recents (all photos, or only the RAWs), the albums, and the photos of the album open.
/// It asks for access once, at the first launch, and follows library changes (a photo taken, a
/// limited selection edited) by fetching again.
///
/// Every fetch runs off the main actor and lands when it is done, so switching Recents and Albums
/// never waits on Photos: the panel keeps showing what it has (or a spinner the first time) and
/// stays scrollable. Recents and the albums are fetched as soon as access is granted, before the
/// user asks. The album list is the slow one (each album is a query for its count and its newest
/// photo), so the first time it is published in small batches as it grows; later reloads swap
/// the whole list at once, so a library change never shrinks the grid under the user's finger.
///
/// Photo lists stay PHFetchResults, which Photos fills lazily, so a library of tens of thousands
/// costs nothing until the grid scrolls to a photo. Only the RAW filter inside an album builds an
/// identifier list, because Photos has no RAW predicate: RAWs are known through the RAW smart
/// album alone. A newer fetch cancels an older one of the same kind, so a stale list never lands.
@Observable
@MainActor
final class PhotoLibraryStore {

    enum Access: Equatable {

        case undetermined
        case denied
        case limited
        case full
    }

    enum Scope: Hashable {

        case recents
        case albums
    }

    private(set) var access: Access

    var scope: Scope = .recents

    var showsOnlyRAW = false {
        didSet { reloadPhotos() }
    }

    /// recents is Recents' photo list, nil until its first fetch lands.
    private(set) var recents: PhotoList?

    /// albums is the album list, nil until its first batch lands.
    private(set) var albums: [PhotoAlbum]?

    /// openAlbum is the album whose photos the Albums scope shows, nil on the album list;
    /// albumPhotos is that album's photo list, nil until its fetch lands.
    private(set) var openAlbum  : PhotoAlbum?
    private(set) var albumPhotos: PhotoList?

    @ObservationIgnored private let changeRelay = ChangeRelay()
    @ObservationIgnored private var recentsTask    : Task<Void, Never>?
    @ObservationIgnored private var albumsTask     : Task<Void, Never>?
    @ObservationIgnored private var albumPhotosTask: Task<Void, Never>?

    init() {
        access = Self.access(for: PHPhotoLibrary.authorizationStatus(for: .readWrite))
        changeRelay.onChange = { [weak self] in self?.reloadAll() }

        if canRead {
            PHPhotoLibrary.shared().register(changeRelay)
            reloadAll()
        }
    }

    /// requestAccess shows the system prompt the first time and does nothing after: the answer
    /// is remembered by the system and changed only in Settings.
    func requestAccess() async {
        guard access == .undetermined else { return }

        access = Self.access(for: await PHPhotoLibrary.requestAuthorization(for: .readWrite))

        if canRead {
            PHPhotoLibrary.shared().register(changeRelay)
            reloadAll()
        }
    }

    func open(_ album: PhotoAlbum) {
        openAlbum   = album
        albumPhotos = nil
        reloadAlbumPhotos()
    }

    /// closeAlbum leaves the album's photos in place, so the page slides out showing them; the
    /// next album replaces them.
    func closeAlbum() {
        albumPhotosTask?.cancel()
        openAlbum = nil
    }

    /// manageLimitedSelection lets a user who granted limited access pick more photos (or fewer).
    /// The change arrives through the library observer.
    func manageLimitedSelection() {
        guard let controller = Self.topViewController() else { return }

        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    private var canRead: Bool {
        access == .limited || access == .full
    }

    private func reloadAll() {
        reloadPhotos()
        reloadAlbums()
    }

    /// reloadPhotos refetches the photo lists the RAW filter applies to.
    private func reloadPhotos() {
        reloadRecents()

        if openAlbum != nil {
            reloadAlbumPhotos()
        }
    }

    private func reloadRecents() {
        guard canRead else { return }

        let onlyRAW = showsOnlyRAW
        recentsTask?.cancel()
        recentsTask = Task { [weak self] in
            let list = await Self.fetchPhotos(in: nil, onlyRAW: onlyRAW)
            guard !Task.isCancelled else { return }

            self?.recents = list
        }
    }

    private func reloadAlbumPhotos() {
        guard canRead, let openAlbum else { return }

        let onlyRAW = showsOnlyRAW
        albumPhotosTask?.cancel()
        albumPhotosTask = Task { [weak self] in
            let list = await Self.fetchPhotos(in: openAlbum, onlyRAW: onlyRAW)
            guard !Task.isCancelled else { return }

            self?.albumPhotos = list
        }
    }

    private func reloadAlbums() {
        guard canRead else { return }

        let isFirstLoad = albums == nil
        albumsTask?.cancel()
        albumsTask = Task { [weak self] in
            let loaded = await Self.fetchAlbums { batch in
                if isFirstLoad {
                    self?.albums = batch
                }
            }
            guard !Task.isCancelled else { return }

            self?.albums = loaded
        }
    }

    // MARK: Fetching, off the main actor

    /// photoOptions keeps still images only, newest first.
    nonisolated private static var photoOptions: PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate       = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }

    /// fetchPhotos lists the photos of an album, or of the whole library when `album` is nil,
    /// keeping only those in the RAW smart album when asked.
    @concurrent
    nonisolated private static func fetchPhotos(in album: PhotoAlbum?, onlyRAW: Bool) async -> PhotoList {
        let rawAlbum = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumRAW, options: nil).firstObject
        let query    = PhotoList.Query(albumIdentifier: album?.id, onlyRAW: onlyRAW)

        switch (album, onlyRAW) {
            case (nil, false):
                return PhotoList(query: query, assets: PHAsset.fetchAssets(with: photoOptions))

            case (nil, true):
                guard let rawAlbum else { return PhotoList(query: query, assets: PHFetchResult()) }
                return PhotoList(query: query, assets: PHAsset.fetchAssets(in: rawAlbum, options: photoOptions))

            case (let album?, false):
                return PhotoList(query: query, assets: PHAsset.fetchAssets(in: album.collection, options: photoOptions))

            case (let album?, true):
                guard let rawAlbum else { return PhotoList(query: query, assets: PHFetchResult()) }

                var rawIdentifiers = Set<String>()
                PHAsset.fetchAssets(in: rawAlbum, options: photoOptions).enumerateObjects { asset, _, _ in
                    rawIdentifiers.insert(asset.localIdentifier)
                }

                var identifiers = [String]()
                PHAsset.fetchAssets(in: album.collection, options: photoOptions).enumerateObjects { asset, _, _ in
                    if rawIdentifiers.contains(asset.localIdentifier) {
                        identifiers.append(asset.localIdentifier)
                    }
                }
                return PhotoList(query: query, assets: PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: photoOptions))
        }
    }

    /// fetchAlbums lists a few useful smart albums, then the user's own, skipping empty ones. It
    /// hands every batch of `batchSize` albums to `publish` on the way, and stops early when the
    /// task is cancelled.
    @concurrent
    nonisolated private static func fetchAlbums(
        publish: @escaping @MainActor @Sendable ([PhotoAlbum]) -> Void
    ) async -> [PhotoAlbum] {
        let batchSize = 8
        let smartSubtypes: [PHAssetCollectionSubtype] = [.smartAlbumFavorites, .smartAlbumRAW, .smartAlbumScreenshots]

        var collections = smartSubtypes.compactMap {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: $0, options: nil).firstObject
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { collection, _, _ in
            collections.append(collection)
        }

        var albums = [PhotoAlbum]()
        for (index, collection) in collections.enumerated() {
            guard !Task.isCancelled else { return albums }

            let photos = PHAsset.fetchAssets(in: collection, options: photoOptions)
            if photos.count > 0 {
                albums.append(PhotoAlbum(
                    collection : collection,
                    title      : collection.localizedTitle ?? "Album",
                    count      : photos.count,
                    keyPhoto   : photos.firstObject
                ))
            }

            if index % batchSize == batchSize - 1 {
                await publish(albums)
            }
        }
        return albums
    }

    nonisolated private static func access(for status: PHAuthorizationStatus) -> Access {
        switch status {
            case .notDetermined:
                return .undetermined

            case .limited:
                return .limited

            case .authorized:
                return .full

            default:
                return .denied
        }
    }

    /// topViewController is the controller on top of the foreground window, which presents the
    /// limited-library picker.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top   = scene?.keyWindow?.rootViewController

        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    /// ChangeRelay forwards library changes to the main actor. Photos calls observers on a
    /// background queue and requires an NSObject, which the store is not.
    @MainActor
    private final class ChangeRelay: NSObject, PHPhotoLibraryChangeObserver {

        var onChange: @MainActor () -> Void = {}

        nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
            Task { @MainActor in self.onChange() }
        }
    }
}

/// PhotoList is one fetched list of photos and the query that produced it. The grid animates a
/// new query (the RAW filter turned on, another album) and swaps a refetch of the same query in
/// place, so a library change never resets the user's scroll.
///
/// Photos model objects (fetch results, assets, collections) are immutable snapshots that Photos
/// lets any thread read, which the type system cannot see: hence the unchecked Sendable here and
/// on PhotoAlbum, so lists fetched off the main actor can be handed to the grid.
nonisolated struct PhotoList: @unchecked Sendable {

    /// Query is what a list holds: an album's photos (nil: the whole library), maybe RAW only.
    struct Query: Hashable, Sendable {

        let albumIdentifier: String?
        let onlyRAW        : Bool
    }

    let query : Query
    let assets: PHFetchResult<PHAsset>

    var count: Int { assets.count }

    func asset(at index: Int) -> PHAsset {
        assets.object(at: index)
    }
}

/// PhotoAlbum is one album card: its collection, title, photo count and the newest photo, which
/// stands for the album on the card.
nonisolated struct PhotoAlbum: Identifiable, Hashable, @unchecked Sendable {

    let collection: PHAssetCollection
    let title     : String
    let count     : Int
    let keyPhoto  : PHAsset?

    var id: String { collection.localIdentifier }
}
