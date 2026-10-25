//
//  AppDelegate.swift
//  iLightCraft
//

import UIKit

/// AppDelegate adapts process service startup to the SwiftUI app lifecycle.
///
/// It opens the one engine session at launch and keeps it, with the memory monitor and the
/// lifecycle observer, for the life of the process. The library is file-locked, so a second session
/// would fail: ContentView takes the engine from here instead of making its own. If the
/// engine does not open, `engineError` says why and the scene shows it instead of the editor.
final class AppDelegate: UIResponder, UIApplicationDelegate {

    /// The engine opens its previews at most this many pixels on the long edge (spec: 2560).
    static let maximumPreviewPixels = 2560

    private(set) var engine     : EngineManager?
    private(set) var engineError: EngineError?

    private var memoryMonitor    : MemoryBudgetMonitor<EngineManager, ProcessAvailableMemory>?
    private var lifecycleObserver: EngineLifecycleObserver<EngineManager>?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        LegacyEditCompatibility.migratePreferences()
        let engine: EngineManager
        let options = MeasurementLaunchOptions(arguments: ProcessInfo.processInfo.arguments)

        let priorRecoveredLibrary = UserDefaults.standard.string(forKey: NativeLibraryLocation.activeKey)
        let recoveryActivated = !options.isFreshEngineDirectory && NativeLibraryLocation.activatePending()
        do {
            if options.isFreshEngineDirectory {
                engine = try EngineManager(
                    dataDirectory : Self.freshEngineDirectory(),
                    maxPixels     : Self.maximumPreviewPixels
                )
            } else {
                engine = try EngineManager(maxPixels: Self.maximumPreviewPixels)
            }
        } catch {
            if recoveryActivated {
                if let priorRecoveredLibrary { UserDefaults.standard.set(priorRecoveredLibrary, forKey: NativeLibraryLocation.activeKey) }
                else { UserDefaults.standard.removeObject(forKey: NativeLibraryLocation.activeKey) }
                UserDefaults.standard.set("Recovery could not open; the previous library was retained.", forKey: "native.recoveryStatus")
                do { engine = try EngineManager(maxPixels: Self.maximumPreviewPixels) }
                catch { engineError = error; return true }
            } else { engineError = error; return true }
        }

        let memoryMonitor = MemoryBudgetMonitor(
            engine : engine,
            memory : ProcessAvailableMemory()
        )

        let lifecycleObserver = EngineLifecycleObserver(engine: engine)

        memoryMonitor.start()
        lifecycleObserver.start()
        engine.recordState(event: "launch")

        self.engine            = engine
        self.memoryMonitor     = memoryMonitor
        self.lifecycleObserver = lifecycleObserver

        return true
    }

    /// freshEngineDirectory is the empty library of `-iLightCraftEngineDir fresh`, for cold-open
    /// measurements: `tmp/FreshEngine`, deleted first, so runs never pile up libraries.
    private static func freshEngineDirectory() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "FreshEngine", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        return directory
    }
}
