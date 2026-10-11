//
//  EditorLaunchRunner.swift
//  Unveil
//

import UIKit

/// EditorLaunchRunner preserves the diagnostic launch arguments independently of the app's
/// scene framework. Each editor starts these commands once, even if its root view reappears.
@MainActor
final class EditorLaunchRunner {

    private var hasStarted: Bool = false

    func start(
        engine : EngineManager,
        session: EditorSession<EngineManager, PhotoImporter, PhotoLibraryLoader>,
        canvas : CanvasView,
        options: MeasurementLaunchOptions
    ) {
        guard !hasStarted else { return }

        hasStarted = true
        runLaunchCommand(engine: engine)
        runMeasurement(
            options : options,
            session : session,
            canvas  : canvas,
            engine  : engine
        )
    }

    /// runLaunchCommand runs the diagnostic named by the `-UnveilRun` launch argument, once per
    /// launch, so an agent can drive the device with no taps (`devicectl device process launch`).
    ///
    /// `golden` exports the reference images, prints its progress and ends the process: `exit(0)` when
    /// every image was written, `exit(1)` otherwise. The exit is allowed only in this agent-driven
    /// mode, where nobody is editing. `state` appends one `engine.jsonl` line and stays open.
    private func runLaunchCommand(engine: EngineManager) {
        guard let command = UserDefaults.standard.string(forKey: "UnveilRun") else { return }

        Task {
            // The engine is suspended while the app is not active: wait for the first activation.
            while UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }

            switch command {
                case "golden":
                    let summary = await GoldenExporter(engine: engine).run()
                    exit(summary.failures.isEmpty ? 0 : 1)

                case "state":
                    engine.recordState(event: "run-state")

                default:
                    print("unknown -UnveilRun value: \(command)")
            }
        }
    }

    /// runMeasurement opens the photo named by `-UnveilOpen` and runs the sweep of `-UnveilSweep`
    /// (see MeasurementLaunchOptions), so T15's runs need no taps. The open goes through the
    /// session, like a pick on the home, so a good open presents the editor. Without
    /// `-UnveilOpen` it does nothing, and a normal launch is unchanged.
    ///
    /// Before the open it waits for an `app.gpu` read on the engine's serial command queue, which
    /// lands behind the launch read (the first one creates the GPU device): so `OpenToFirstFrame`
    /// starts after that cost, and the launch read shows apart as its own `Command` interval.
    ///
    /// With `-UnveilExitAfterSweep` the process ends when the sweep does, `exit(0)` only when it ran
    /// its full time, and `exit(1)` if the photo never showed a full frame. Like `-UnveilRun golden`,
    /// the exit is allowed only in this agent-driven mode, where nobody is editing.
    private func runMeasurement(
        options: MeasurementLaunchOptions,
        session: EditorSession<EngineManager, PhotoImporter, PhotoLibraryLoader>,
        canvas : CanvasView,
        engine : EngineManager
    ) {
        guard let fileName = options.openFileName else { return }

        let viewModel = session.viewModel

        Task {
            while UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }

            try? await Task.sleep(for: .seconds(options.delaySeconds))
            _ = try? await engine.diagnostic("app.gpu", params: [String: String]())

            print("measure: opening \(fileName)")
            await session.open(pickedURL: URL.documentsDirectory.appending(path: "raw/\(fileName)"))

            guard await Self.waitForFullFrame(in: engine.frames) else {
                print("measure: no full frame for \(fileName): \(viewModel.errorMessage ?? "timed out")")
                if options.exitsAfterSweep { exit(1) }
                return
            }

            print("measure: first full frame")

            if let panel = options.openPanel {
                session.showPanel(panel)
            }

            if let percent = options.zoomPercent {
                canvas.zoom(toPercent: percent)
            }

            if options.cyclesZoom {
                await Self.cycleZoom(canvas, engine: engine)
                if options.exitsAfterSweep { exit(0) }
                return
            }

            guard let seconds = options.sweepSeconds else { return }

            let sweep = StressSweep(viewModel: viewModel, duration: seconds) { isComplete, _ in
                canvas.isMeasurementPanning = false
                if options.exitsAfterSweep { exit(isComplete ? 0 : 1) }
            }

            sweep.start()

            if options.pansDuringSweep {
                // A pan stops a running spring: let the zoom animation land first.
                try? await Task.sleep(for: .seconds(1))
                await Self.pan(canvas, for: seconds - 1)
            }
        }
    }

    /// pan moves the canvas along its measurement circle about every 16 ms for `seconds`, the pan
    /// half of a `-UnveilPanSweep` run, then lets it rest so the window is rendered at full quality.
    private static func pan(_ canvas: CanvasView, for seconds: Double) async {
        let start = ContinuousClock.now

        canvas.isMeasurementPanning = true

        while canvas.isMeasurementPanning, start.duration(to: .now) < .seconds(seconds) {
            let elapsed = start.duration(to: .now) / .seconds(1)
            canvas.measurementPan(at: elapsed)

            try? await Task.sleep(for: .milliseconds(16))
        }

        canvas.isMeasurementPanning = false
    }

    /// cycleZoom is the `-UnveilZoomCycle` run, with FootprintSampler writing the memory CSV: 20 s at
    /// fit, then three times 100 % and back to fit. The first zoom is cold, the second follows 20 s
    /// at fit (the window memory was released 2 s in), the third only 1 s (nothing released). It
    /// prints when each phase starts, how long each zoom took from its start (spring included) to
    /// its first window and first full window, and the engine's `library.memory` after each hold.
    private static func cycleZoom(_ canvas: CanvasView, engine: EngineManager) async {
        let sampler = FootprintSampler()
        let start   = ContinuousClock.now
        let frames  = engine.frames

        func report(_ phase: String) async {
            let memory = (try? await engine.diagnostic("library.memory", params: [String: String]())) ?? "?"
            print("cycle: \(phase) memory \(memory)")
        }

        UIApplication.shared.isIdleTimerDisabled = true
        sampler.start()
        print("cycle: fit at \(start.duration(to: .now))")
        try? await Task.sleep(for: .seconds(20))
        await report("fit")

        for (round, zoomedHold, fitHold) in [(1, 20, 20), (2, 10, 1), (3, 10, 20)] {
            let before = frames.published().window?.generation ?? 0
            let zoomed = ContinuousClock.now
            var first  : Duration?

            print("cycle: zoom \(round) at \(start.duration(to: zoomed))")
            canvas.zoom(toPercent: 100)

            while zoomed.duration(to: .now) < .seconds(30) {
                if let window = frames.published().window, window.generation > before {
                    first = first ?? zoomed.duration(to: .now)
                    if !window.isDraft { break }
                }

                try? await Task.sleep(for: .milliseconds(5))
            }

            let full = zoomed.duration(to: .now)
            print("cycle: zoom \(round) first window after \(first ?? full), first full window after \(full)")
            try? await Task.sleep(for: .seconds(zoomedHold))
            await report("zoom \(round)")

            print("cycle: fit \(round) at \(start.duration(to: .now))")
            canvas.zoomToFit()
            try? await Task.sleep(for: .seconds(fitHold))
            await report("fit \(round)")
        }

        await sampler.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        print("cycle: done at \(start.duration(to: .now))")
    }

    /// waitForFullFrame polls the sink every 20 ms, for at most 60 s, until it holds a full frame.
    /// The sink starts empty at launch, so the first full frame is the open's preview.
    private static func waitForFullFrame(in frames: FrameSink) async -> Bool {
        for _ in 0 ..< 3000 {
            if let frame = frames.latest(), !frame.isDraft { return true }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return false
    }

    /// exitIfAgentDriven ends the process with `exit(1)` when a launch argument asked for an
    /// agent-driven run (`-UnveilRun`, `-UnveilOpen`) and the engine is not there to run it: the
    /// devicectl caller then sees the failure at once instead of waiting for its own timeout.
    static func exitIfAgentDriven(reason: String) {
        let isAgentDriven = UserDefaults.standard.string(forKey: "UnveilRun") != nil
            || MeasurementLaunchOptions(arguments: ProcessInfo.processInfo.arguments).openFileName != nil

        guard isAgentDriven else { return }

        print("engine unavailable: \(reason)")
        exit(1)
    }
}
