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
        engine   : EngineManager,
        viewModel: EditorViewModel<EngineManager, PhotoImporter>,
        showPanel: @escaping @MainActor (AdjustmentGroup) -> Void
    ) {
        guard !hasStarted else { return }

        hasStarted = true
        runLaunchCommand(engine: engine)
        runMeasurement(
            options   : MeasurementLaunchOptions(arguments: ProcessInfo.processInfo.arguments),
            viewModel : viewModel,
            engine    : engine,
            showPanel : showPanel
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
    /// (see MeasurementLaunchOptions), so T15's runs need no taps. Without `-UnveilOpen` it does
    /// nothing, and a normal launch is unchanged.
    ///
    /// Before the open it waits for an `app.gpu` read on the engine's serial command queue, which
    /// lands behind the launch read (the first one creates the GPU device): so `OpenToFirstFrame`
    /// starts after that cost, and the launch read shows apart as its own `Command` interval.
    ///
    /// With `-UnveilExitAfterSweep` the process ends when the sweep does, `exit(0)` only when it ran
    /// its full time, and `exit(1)` if the photo never showed a full frame. Like `-UnveilRun golden`,
    /// the exit is allowed only in this agent-driven mode, where nobody is editing.
    private func runMeasurement(
        options  : MeasurementLaunchOptions,
        viewModel: EditorViewModel<EngineManager, PhotoImporter>,
        engine   : EngineManager,
        showPanel: @escaping @MainActor (AdjustmentGroup) -> Void
    ) {
        guard let fileName = options.openFileName else { return }

        Task {
            while UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }

            try? await Task.sleep(for: .seconds(options.delaySeconds))
            _ = try? await engine.diagnostic("app.gpu", params: [String: String]())

            print("measure: opening \(fileName)")
            await viewModel.open(pickedURL: URL.documentsDirectory.appending(path: "raw/\(fileName)"))

            guard await Self.waitForFullFrame(in: engine.frames) else {
                print("measure: no full frame for \(fileName): \(viewModel.errorMessage ?? "timed out")")
                if options.exitsAfterSweep { exit(1) }
                return
            }

            print("measure: first full frame")

            if let panel = options.openPanel {
                showPanel(panel)
            }

            guard let seconds = options.sweepSeconds else { return }

            let sweep = StressSweep(viewModel: viewModel, duration: seconds) { isComplete, _ in
                if options.exitsAfterSweep { exit(isComplete ? 0 : 1) }
            }

            sweep.start()
        }
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
