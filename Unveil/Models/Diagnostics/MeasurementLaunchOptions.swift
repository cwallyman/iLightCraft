//
//  MeasurementLaunchOptions.swift
//  Unveil
//

import Foundation

/// MeasurementLaunchOptions are the launch arguments that let an agent run T15's measurements with
/// no taps (`devicectl device process launch <bundle> -- <arguments>`):
///
/// - `-UnveilOpen <name>`: open `Documents/raw/<name>` through the editor once the app is active;
/// - `-UnveilDelay <s>`: wait that long first (default 0), so xctrace can attach before the open;
/// - `-UnveilSweep <s>`: after the first full frame, run StressSweep for that many seconds;
/// - `-UnveilEngineDir fresh`: open the engine on a new, empty library, so the open is cold;
/// - `-UnveilExitAfterSweep`: end the process when the sweep ends (0 if it ran its full time);
/// - `-UnveilPanel <name>`: after the first full frame, open that adjustment panel ("Light",
///   "Color"...: the group title, any case), so a screenshot of a panel needs no tap;
/// - `-UnveilZoom <percent>`: after the first full frame, zoom to that percentage of the photo's real
///   pixels (clamped to the zoom range), so a screenshot of a zoom level needs no pinch;
/// - `-UnveilPanSweep`: during the sweep, also pan the canvas in a circle (CanvasView.measurementPan),
///   so a zoomed sweep moves the visible window as a finger would;
/// - `-UnveilZoomCycle`: instead of a sweep, zoom between fit and 100 % three times, then pinch to
///   400 % and back, while the memory CSV is written, printing how long each zoom takes to its first
///   window; a Debug build also writes the hitch table of each phase (FrameTimingProbe);
/// - `-UnveilExposure <ev>`: after the first full frame, set the exposure to that value (it may be
///   negative), committed like a released slider, so a screenshot of a clipping photo needs no drag;
/// - `-UnveilClipping`: after the first full frame, turn on both clipping overlays (they show with
///   the card, so pair it with `-UnveilPanel`);
/// - `-UnveilBefore`: after the first full frame (and the exposure), show the unedited look, so a
///   screenshot of the before view needs no press and hold;
/// - `-UnveilHomePhotos`: start the home's panel on Photos instead of Files;
/// - `-UnveilHomeExpanded`: start the home's panel at full height, so its screenshot needs no drag.
///
/// `allowsImportSweep` is false under any of them, or any other `-Unveil...` argument (the
/// `-UnveilRun` disk report, say): see its doc.
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

    /// allowsImportSweep is the one gate of the import orphan sweep: true only for a plain launch,
    /// with no `-Unveil...` argument at all and not as the host of a test run (XCTest's
    /// `XCTestConfigurationFilePath` in the environment); the tests call the sweep directly.
    /// A fresh or other engine directory (`-UnveilEngineDir`) has a catalog that does not
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

        openFileName           = value(after: "-UnveilOpen")
        delaySeconds           = nonNegativeNumber(after: "-UnveilDelay") ?? 0
        sweepSeconds           = positiveNumber(after: "-UnveilSweep")
        isFreshEngineDirectory = value(after: "-UnveilEngineDir") == "fresh"
        exitsAfterSweep        = arguments.contains("-UnveilExitAfterSweep")
        openPanel              = value(after: "-UnveilPanel").flatMap { name in
            AdjustmentGroup.allCases.first { $0.title.lowercased() == name.lowercased() }
        }
        zoomPercent            = positiveNumber(after: "-UnveilZoom")
        pansDuringSweep        = arguments.contains("-UnveilPanSweep")
        cyclesZoom             = arguments.contains("-UnveilZoomCycle")
        exposure               = value(after: "-UnveilExposure").flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        showsClipping          = arguments.contains("-UnveilClipping")
        showsBefore            = arguments.contains("-UnveilBefore")
        startsHomeOnPhotos     = arguments.contains("-UnveilHomePhotos")
        startsHomeExpanded     = arguments.contains("-UnveilHomeExpanded")
        allowsImportSweep      = !arguments.contains { $0.hasPrefix("-Unveil") }
            && environment["XCTestConfigurationFilePath"] == nil
    }
}
