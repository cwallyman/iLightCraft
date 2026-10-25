//
//  MeasurementLaunchOptions.swift
//  iLightCraft
//

import Foundation

/// MeasurementLaunchOptions are the launch arguments that let an agent run T15's measurements with
/// no taps (`devicectl device process launch <bundle> -- <arguments>`):
///
/// - `-iLightCraftOpen <name>`: open `Documents/raw/<name>` through the editor once the app is active;
/// - `-iLightCraftDelay <s>`: wait that long first (default 0), so xctrace can attach before the open;
/// - `-iLightCraftSweep <s>`: after the first full frame, run StressSweep for that many seconds;
/// - `-iLightCraftEngineDir fresh`: open the engine on a new, empty library, so the open is cold;
/// - `-iLightCraftExitAfterSweep`: end the process when the sweep ends (0 if it ran its full time);
/// - `-iLightCraftPanel <name>`: after the first full frame, open that adjustment panel ("Light",
///   "Color"...: the group title, any case), so a screenshot of a panel needs no tap;
/// - `-iLightCraftZoom <percent>`: after the first full frame, zoom to that percentage of the photo's real
///   pixels (clamped to the zoom range), so a screenshot of a zoom level needs no pinch;
/// - `-iLightCraftPanSweep`: during the sweep, also pan the canvas in a circle (CanvasView.measurementPan),
///   so a zoomed sweep moves the visible window as a finger would;
/// - `-iLightCraftZoomCycle`: instead of a sweep, zoom between fit and 100 % three times, then pinch to
///   400 % and back, while the memory CSV is written, printing how long each zoom takes to its first
///   window; a Debug build also writes the hitch table of each phase (FrameTimingProbe);
/// - `-iLightCraftExposure <ev>`: after the first full frame, set the exposure to that value (it may be
///   negative), committed like a released slider, so a screenshot of a clipping photo needs no drag;
/// - `-iLightCraftClipping`: after the first full frame, turn on both clipping overlays (they show with
///   the card, so pair it with `-iLightCraftPanel`);
/// - `-iLightCraftBefore`: after the first full frame (and the exposure), show the unedited look, so a
///   screenshot of the before view needs no press and hold;
/// - `-iLightCraftHomePhotos`: start the home's panel on Photos instead of Files;
/// - `-iLightCraftHomeExpanded`: start the home's panel at full height, so its screenshot needs no drag;
/// - `-iLightCraftRecordInput <s>`: a Debug build records the canvas's input events and display updates
///   for that many seconds (InputRecorder), from the first full frame of `-iLightCraftOpen` or else from
///   launch, so a hand-made trackpad session leaves a CSV; with `-iLightCraftExitAfterSweep` it then ends.
/// - `-iLightCraftMemoryMap`: after the first full frame, take the E0 memory map at four moments (open, fit,
///   100 %, back at fit), printing one `MM` line each (MemoryMapReport);
/// - `-iLightCraftTimeline`: print the open's phases and the engine's file loads (`TL` lines);
/// - `-iLightCraftCost`: around the sweep, print its CPU, energy, GPU and render totals (`COST` line);
/// - `-iLightCraftSweepFull`: the sweep releases on every tick, so every frame is a full render.
///
/// `allowsImportSweep` is false under any of them, or any other `-iLightCraft...` argument (the
/// `-iLightCraftRun` disk report, say): see its doc.
///
/// They are parsed by hand, not through UserDefaults, because several are flags with no value.
/// A number that does not parse, or is negative, or not finite, counts as absent.
nonisolated struct MeasurementLaunchOptions: Equatable, Sendable {

    let openFileName          : String?
    let delaySeconds          : Double
    let sweepSeconds          : Double?
    let isFreshEngineDirectory: Bool
    let exitsAfterSweep       : Bool
    let openPanel             : AdjustmentGroup?
    let zoomPercent           : Double?
    let pansDuringSweep       : Bool
    let cyclesZoom            : Bool
    let exposure              : Double?
    let showsClipping         : Bool
    let showsBefore           : Bool
    let startsHomeOnPhotos    : Bool
    let startsHomeExpanded    : Bool
    let recordInputSeconds    : Double?
    let reportsMemoryMap      : Bool
    let reportsTimeline       : Bool
    let reportsCost           : Bool
    let releasesEveryTick     : Bool

    /// allowsImportSweep is the one gate of the import orphan sweep: true only for a plain launch,
    /// with no `-iLightCraft...` argument at all and not as the host of a test run (XCTest's
    /// `XCTestConfigurationFilePath` in the environment); the tests call the sweep directly.
    /// A fresh or other engine directory (`-iLightCraftEngineDir`) has a catalog that does not
    /// describe the shared Imports folder, so a sweep there would delete the real library's
    /// copies; a measurement or agent run must not change the disk it reads. Matching the
    /// prefix keeps a future option safe without a change here.
    let allowsImportSweep     : Bool

    init(
        arguments  : [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        func nonNegativeNumber(after flag: String) -> Double? {
            guard let number = value(after: flag).flatMap(Double.init),
                  number.isFinite,
                  number >= 0
            else {
                return nil
            }

            return number
        }

        func positiveNumber(after flag: String) -> Double? {
            nonNegativeNumber(after: flag).flatMap { $0 > 0 ? $0 : nil }
        }

        openFileName           = value(after: "-iLightCraftOpen")
        delaySeconds           = nonNegativeNumber(after: "-iLightCraftDelay") ?? 0
        sweepSeconds           = positiveNumber(after: "-iLightCraftSweep")
        isFreshEngineDirectory = value(after: "-iLightCraftEngineDir") == "fresh"
        exitsAfterSweep        = arguments.contains("-iLightCraftExitAfterSweep")
        openPanel              = value(after: "-iLightCraftPanel").flatMap { name in
            AdjustmentGroup.allCases.first { $0.title.lowercased() == name.lowercased() }
        }
        zoomPercent            = positiveNumber(after: "-iLightCraftZoom")
        pansDuringSweep        = arguments.contains("-iLightCraftPanSweep")
        cyclesZoom             = arguments.contains("-iLightCraftZoomCycle")
        exposure               = value(after: "-iLightCraftExposure").flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        showsClipping          = arguments.contains("-iLightCraftClipping")
        showsBefore            = arguments.contains("-iLightCraftBefore")
        startsHomeOnPhotos     = arguments.contains("-iLightCraftHomePhotos")
        startsHomeExpanded     = arguments.contains("-iLightCraftHomeExpanded")
        recordInputSeconds     = positiveNumber(after: "-iLightCraftRecordInput")
        reportsMemoryMap       = arguments.contains("-iLightCraftMemoryMap")
        reportsTimeline        = arguments.contains("-iLightCraftTimeline")
        reportsCost            = arguments.contains("-iLightCraftCost")
        releasesEveryTick      = arguments.contains("-iLightCraftSweepFull")
        allowsImportSweep      = !arguments.contains { $0.hasPrefix("-iLightCraft") }
            && environment["XCTestConfigurationFilePath"] == nil
    }
}
