//
//  EditorDiagnostics.swift
//  iLightCraft
//

import Foundation

/// EditorDiagnostics keeps asynchronous diagnostic commands and the stress sweep alive apart
/// from the menu's view lifetime. Results are plain alert values delivered to the editor session.
@MainActor
final class EditorDiagnostics<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {

    private let engine           : Engine
    private let viewModel        : EditorViewModel<Engine, Importer>
    private let possibleTearCount: () -> Int
    private let present          : (EditorAlert) -> Void
    private let cleanUpImports   : () async -> ImportSweepReport
    private let testData         : TestDataCleaner

    private var soakTest: StressSweep<Engine, Importer>?

    init(
        engine           : Engine,
        viewModel        : EditorViewModel<Engine, Importer>,
        possibleTearCount: @escaping () -> Int,
        present          : @escaping (EditorAlert) -> Void,
        cleanUpImports   : @escaping () async -> ImportSweepReport = { .nothing },
        testData         : TestDataCleaner = TestDataCleaner()
    ) {
        self.engine           = engine
        self.viewModel        = viewModel
        self.possibleTearCount = possibleTearCount
        self.present          = present
        self.cleanUpImports   = cleanUpImports
        self.testData         = testData
    }

    /// showEngineState reads and logs the backend and memory state. A diagnostic failure is
    /// presented as a result too, so an unavailable engine never leaves the menu action silent.
    func showEngineState() async {
        let gpu   : String
        let memory: String
        let tears = possibleTearCount()

        do {
            gpu    = try await engine.diagnostic("app.gpu", params: [String: String]())
            memory = try await engine.diagnostic("library.memory", params: [String: String]())
        } catch {
            present(EditorAlert(
                title   : "Engine state",
                message : "Could not read engine state: \(error.message)"
            ))
            return
        }

        EngineStateLog.append(
            event         : "menu",
            gpu           : gpu,
            possibleTears : tears
        )
        present(EditorAlert(
            title   : "Engine state",
            message : "app.gpu: \(gpu)\n\nlibrary.memory: \(memory)\n\npossibleTears: \(tears)"
        ))
    }

    /// exportReferenceImages runs the existing golden exporter and reports both the saved
    /// image count and individual failures without coupling the exporter to presentation.
    func exportReferenceImages() async {
        let summary = await GoldenExporter(engine: engine).run()
        var message = "Saved \(summary.written) reference images to Documents/golden."
        if !summary.failures.isEmpty {
            message += "\n\nFailed:\n" + summary.failures.joined(separator: "\n")
        }

        present(EditorAlert(title: "Reference images", message: message))
    }

    /// cleanUpTestData deletes the generated golden and measurement folders, sweeps the orphan
    /// import copies, and says what it freed.
    func cleanUpTestData() async {
        let testBytes = await testData.removeAll()
        let imports   = await cleanUpImports()
        let total     = (testBytes + imports.freedBytes).formatted(.byteCount(style: .file))
        let testSize  = testBytes.formatted(.byteCount(style: .file))
        let copySize  = imports.freedBytes.formatted(.byteCount(style: .file))

        present(EditorAlert(
            title   : "Clean Up Test Data",
            message : "Freed \(total): test output \(testSize), "
                + "\(imports.removedCount) unused import copies \(copySize)."
        ))
    }

    /// startSoakTest retains one sweep until it ends, including when the menu disappears.
    func startSoakTest() {
        guard viewModel.isPhotoOpen, soakTest == nil else { return }

        let sweep = StressSweep(viewModel: viewModel, duration: 600) { [weak self] isComplete, csv in
            guard let self else { return }

            soakTest = nil
            present(EditorAlert(
                title   : isComplete ? "Stress Test Complete" : "Stress Test Stopped",
                message : "Saved memory log to Documents/measurements/\(csv.lastPathComponent)."
            ))
        }

        soakTest = sweep
        sweep.start()
    }

    /// injectTestFrame preserves the test gradient's axes and channels, and never overwrites
    /// the preview of an open photo.
    func injectTestFrame() {
        guard !viewModel.isPhotoOpen else { return }

        let side     = 512
        let rowBytes = side * 4
        var pixels   = [UInt8](repeating: 255, count: rowBytes * side)

        for row in 0 ..< side {
            for column in 0 ..< side {
                let offset = row * rowBytes + column * 4
                pixels[offset]     = UInt8(column * 255 / (side - 1))
                pixels[offset + 1] = UInt8(row * 255 / (side - 1))
                pixels[offset + 2] = 64
            }
        }

        pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }

            engine.frames.receive(
                rgba       : base,
                width      : side,
                height     : side,
                stride     : rowBytes,
                generation : 0,
                isDraft    : false
            )
        }
    }
}
