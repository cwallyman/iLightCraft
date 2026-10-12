//
//  ImportStoreTests.swift
//  UnveilTests
//

import Foundation
import Testing
@testable import Unveil

/// A class, so `deinit` removes each test's folder: Swift Testing makes one instance per test.
final class ImportStoreTests {

    let root   : URL
    let imports: URL

    /// A name the catalog answers with in tests that are not about an empty catalog, which the
    /// sweep refuses to act on.
    let otherPhoto = "elsewhere.NEF"

    init() throws {
        root    = FileManager.default.temporaryDirectory.appending(
            path          : "sweep-\(UUID())",
            directoryHint : .isDirectory
        )
        imports = root.appending(path: "Imports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// file writes `byteCount` bytes at `url`, last modified `age` seconds ago.
    @discardableResult
    func file(_ url: URL, byteCount: Int = 10, age: TimeInterval = 3600) throws -> URL {
        try Data(count: byteCount).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-age)],
            ofItemAtPath: url.path
        )
        return url
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func store(_ catalog: FakeImportCatalog) -> ImportStore<FakeImportCatalog> {
        ImportStore(catalog: catalog, importsDirectory: imports)
    }

    @Test
    func anOrphanIsRemovedAndReported() async throws {
        let orphan = try file(imports.appending(path: "orphan.NEF"), byteCount: 100)

        let report = await store(FakeImportCatalog(names: [otherPhoto])).sweep(keeping: nil)

        #expect(!exists(orphan))
        #expect(report == ImportSweepReport(removedCount: 1, freedBytes: 100))
    }

    @Test
    func aReferencedCopyStays() async throws {
        let kept = try file(imports.appending(path: "kept.NEF"))

        _ = await store(FakeImportCatalog(names: ["kept.NEF"])).sweep(keeping: nil)

        #expect(exists(kept))
    }

    @Test
    func theOpenPhotosCopyStays() async throws {
        let open = try file(imports.appending(path: "open.NEF"))

        _ = await store(FakeImportCatalog(names: [otherPhoto])).sweep(keeping: open)

        #expect(exists(open))
    }

    @Test
    func aCopyMadeInTheLastTenMinutesStays() async throws {
        let recent = try file(imports.appending(path: "recent.NEF"), age: 60)
        let old    = try file(imports.appending(path: "old.NEF"), age: 601)

        _ = await store(FakeImportCatalog(names: [otherPhoto])).sweep(keeping: nil)

        #expect(exists(recent))
        #expect(!exists(old))
    }

    @Test
    func filesOutsideImportsAndSymlinksAndFoldersAreUntouched() async throws {
        let outside = try file(root.appending(path: "outside.NEF"))
        let nested  = imports.appending(path: "nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let inner = try file(nested.appending(path: "inner.NEF"))
        let link  = imports.appending(path: "link.NEF")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        _ = await store(FakeImportCatalog(names: [otherPhoto])).sweep(keeping: nil)

        #expect(exists(outside))
        #expect(exists(inner))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
    }

    @Test
    func aCatalogFailureDeletesNothing() async throws {
        let orphan  = try file(imports.appending(path: "orphan.NEF"))
        let catalog = FakeImportCatalog(failure: .engine("catalog.query listed 3 photos, total 4"))

        let report = await store(catalog).sweep(keeping: nil)

        #expect(exists(orphan))
        #expect(report == .nothing)
    }

    /// An empty catalog beside a folder of copies is more likely the wrong library than none.
    @Test
    func anEmptyCatalogDeletesNothing() async throws {
        let copy = try file(imports.appending(path: "copy.NEF"))

        let report = await store(FakeImportCatalog()).sweep(keeping: nil)

        #expect(exists(copy))
        #expect(report == .nothing)
    }

    @Test
    func aMissingImportsFolderIsNotAnError() async {
        let report = await ImportStore(
            catalog          : FakeImportCatalog(names: [otherPhoto]),
            importsDirectory : root.appending(path: "nowhere")
        ).sweep(keeping: nil)

        #expect(report == .nothing)
    }

    /// Only a plain launch sweeps: any measurement or diagnostic option, the fresh engine directory
    /// above all, turns the sweep off.
    @Test(arguments: [
        ["-UnveilEngineDir", "fresh"],
        ["-UnveilEngineDir", "other"],
        ["-UnveilOpen", "DSC0001.NEF"],
        ["-UnveilSweep", "30"],
        ["-UnveilZoomCycle"],
        ["-UnveilRun", "disk"],
        ["-UnveilHomePhotos"],
    ])
    func anyUnveilLaunchOptionTurnsTheSweepOff(_ options: [String]) {
        let launch = MeasurementLaunchOptions(
            arguments   : ["/app/Unveil"] + options,
            environment : [:]
        )
        #expect(!launch.allowsImportSweep)
    }

    @Test
    func aPlainLaunchSweeps() {
        let launch = MeasurementLaunchOptions(arguments: ["/app/Unveil"], environment: [:])
        #expect(launch.allowsImportSweep)
    }

    /// This process hosts the tests, so its real environment must turn the sweep off.
    @Test
    func theHostOfATestRunDoesNotSweep() {
        let environment = ProcessInfo.processInfo.environment
        #expect(environment["XCTestConfigurationFilePath"] != nil)
        #expect(!MeasurementLaunchOptions(arguments: ["/app/Unveil"]).allowsImportSweep)
    }

    @Test
    func theTestDataCleanerRemovesOnlyItsFolders() async throws {
        let golden = root.appending(path: "golden", directoryHint: .isDirectory)
        let raw    = root.appending(path: "raw", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: golden, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try file(golden.appending(path: "a.png"), byteCount: 40)
        let photo = try file(raw.appending(path: "keep.NEF"))

        let cleaner = TestDataCleaner(directories: [golden, root.appending(path: "measurements")])
        let freed   = await cleaner.removeAll()

        #expect(freed == 40)
        #expect(!exists(golden))
        #expect(exists(photo))
    }
}
