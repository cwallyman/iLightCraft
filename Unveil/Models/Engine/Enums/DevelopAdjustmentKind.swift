//
//  DevelopAdjustmentKind.swift
//  Unveil
//

// nonisolated: EngineManager sends these to the engine off the main actor, and the app default is MainActor.
/// DevelopAdjustmentKind names each develop control the editor exposes. The raw value is the engine's control id.
/// The slider numbers mirror Engine/crates/develop/src/controls.rs; keep them in step if the engine changes.
nonisolated enum DevelopAdjustmentKind: String, CaseIterable, Sendable {

    case exposure       = "light.exposure"
    case contrast       = "light.contrast"
    case highlights     = "light.highlights"
    case shadows        = "light.shadows"
    case whites         = "light.whites"
    case blacks         = "light.blacks"
    case temperature    = "wb.temp"
    case tint           = "wb.tint"
    case vibrance       = "color.vibrance"
    case saturation     = "color.saturation"
    case texture        = "effects.texture"
    case clarity        = "effects.clarity"
    case dehaze         = "effects.dehaze"
    case sharpening     = "detail.sharpenAmount"
    case noiseReduction = "detail.nrLuminance"
    case colorNoise     = "detail.nrColor"
    case vignette       = "vignette.amount"
    case grain          = "grain.amount"

    /// range is the slider's bounds. The engine clamps out-of-range values to it as well.
    var range       : ClosedRange<Double> { tuning.range }
    var defaultValue: Double              { tuning.defaultValue }
    /// step is the slider increment: 0.01 for exposure, 50 K for temperature, whole units for the rest.
    var step        : Double              { tuning.step }

    /// snapped(_:) rounds `value` to the step grid, then clamps it to the range. A fractional step
    /// divides by its inverse (100 for 0.01), because 70 * 0.01 is 0.7000000000000001 in binary.
    func snapped(_ value: Double) -> Double {
        let rounded = step >= 1
            ? (value / step).rounded() * step
            : (value * (1 / step)).rounded() / (1 / step)

        return min(max(rounded, range.lowerBound), range.upperBound)
    }

    /// isWhiteBalance is true for temperature and tint, whose default is the photo's As Shot value.
    var isWhiteBalance: Bool { self == .temperature || self == .tint }

    /// tuning is the one table of slider numbers, one row per kind.
    private var tuning: (range: ClosedRange<Double>, defaultValue: Double, step: Double) {
        switch self {
            case .exposure:
                return (-5 ... 5, 0, 0.01)

            case .temperature:
                return (2000 ... 50000, 6500, 50)

            case .tint:
                return (-150 ... 150, 0, 1)

            case .sharpening:
                return (0 ... 150, 0, 1)

            case .noiseReduction, .colorNoise, .grain:
                return (0 ... 100, 0, 1)

            case .contrast, .highlights, .shadows, .whites, .blacks, .vibrance, .saturation,
                 .texture, .clarity, .dehaze, .vignette:
                return (-100 ... 100, 0, 1)
        }
    }
}
