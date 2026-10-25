//
//  ImportSweeper.swift
//  iLightCraft
//

import Foundation

/// ImportSweeper runs the store's sweep on request, one pass at a time: each pass starts only after
/// the one before it ends. A request while a pass is queued and not started adds nothing (that pass
/// will see the same catalog), so a burst of opens costs at most the running pass and one more.
/// The Debug command's `sweepNow` queues behind them the same way and waits for its own pass.
///
/// EditorWorkspace makes one only when `MeasurementLaunchOptions.allowsImportSweep`, so every path
/// that sweeps (launch, after an open, the Debug command) goes through that one gate.
@MainActor
final class ImportSweeper<Catalog: ImportCatalogReading> {

    private let store   : ImportStore<Catalog>
    private let openCopy: () -> URL?

    private var lastPass       : Task<ImportSweepReport, Never>?
    private var isRequestQueued: Bool = false

    init(store: ImportStore<Catalog>, openCopy: @escaping () -> URL?) {
        self.store    = store
        self.openCopy = openCopy
    }

    func request() {
        guard !isRequestQueued else { return }

        isRequestQueued = true
        _ = enqueuePass()
    }

    /// sweepNow waits for its own pass and returns what it freed, for the Debug menu.
    func sweepNow() async -> ImportSweepReport {
        await enqueuePass().value
    }

    private func enqueuePass() -> Task<ImportSweepReport, Never> {
        let previous = lastPass
        let pass     = Task {
            _ = await previous?.value

            // A request from now on needs its own pass: this one may read the catalog first.
            isRequestQueued = false
            return await store.sweep(keeping: openCopy())
        }

        lastPass = pass
        return pass
    }
}
