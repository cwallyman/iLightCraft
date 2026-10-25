//
//  ZoomScale.swift
//  iLightCraft
//

import CoreGraphics
import Foundation

/// ZoomScale converts between the canvas zoom (1 is aspect fit) and the percentage the user reads
/// (100 % is one photo pixel on one screen pixel), and owns the rules built on that: the allowed
/// range, the preset steps, the landmarks that tick, and the pill's text.
///
/// Everything hangs on `percentAtFit`, the real percentage shown at zoom 1, so one value turns a
/// zoom into a percentage (`zoom * percentAtFit`) and back. The range is 5 % to 3200 % of the
/// photo's real pixels, widened to fit when fit is outside it: a photo so large that fit is
/// below 5 %, or so small that fit is above 3200 %.
nonisolated struct ZoomScale: Equatable, Sendable {

    /// steps are the presets of the menu and of Zoom In / Zoom Out, in real percent.
    static let steps: [Double] = [
        5, 6.25, 8.33, 12.5, 16.67, 25, 33.33, 50, 66.67,
        100, 200, 300, 400, 600, 800, 1200, 1600, 2400, 3200
    ]

    static let minimumPercent = 5.0
    static let maximumPercent = 3200.0

    /// stepTolerance keeps a zoom a hair off a step (a spring that stopped at 99.99 %) from
    /// counting as below it, so Zoom In from there goes to the next step and not to the same one.
    private static let stepTolerance = 0.002

    /// realPixelsSnap is how far from the real 100 %, as a fraction of it, a zoom may come to rest
    /// and still be snapped onto it (see `restingZoom(for:)`).
    static let realPixelsSnap = 0.005

    /// rearmBand is how far, as a fraction of the landmark's zoom, the zoom must move away from a
    /// landmark that just ticked before that landmark can tick again (see `landmarkTick`).
    static let rearmBand = 0.02

    /// indirectPinchExponent damps a trackpad pinch: its scale is raised to this power, so a
    /// trackpad doubling zooms by about 1.68x. A calibration knob, tuned from the F5 recording: the
    /// earlier 0.4 to 0.5 was applied to a cumulative scale as if it were a step, which compounded
    /// to an effective exponent of about 1.5 (0.3 to 4, erratic) that the user found too sensitive.
    /// Finger pinches are not damped.
    static let indirectPinchExponent = 0.75

    /// scrollZoomRate is the zoom, as a natural logarithm, per point of Cmd + scroll: 100 points
    /// of trackpad swipe or about ten wheel clicks zoom by 1.5x. A calibration knob like the pinch's.
    static let scrollZoomRate = 0.004

    /// percentAtFit is the real percentage at zoom 1.
    let percentAtFit: Double

    /// init(percentAtFit:) is nil unless the value is a positive, finite number.
    init?(percentAtFit: Double) {
        guard percentAtFit.isFinite, percentAtFit > 0 else { return nil }

        self.percentAtFit = percentAtFit
    }

    /// init(viewSize:imageSize:screenScale:photoScale:) derives `percentAtFit`: view points per
    /// preview pixel at fit, times screen pixels per point, times preview pixels per photo pixel.
    /// It is nil while any of those is unknown.
    init?(
        viewSize   : CGSize,
        imageSize  : CGSize,
        screenScale: Double,
        photoScale : Double
    ) {
        guard let fitScale = CanvasTransform.fitScale(viewSize: viewSize, imageSize: imageSize) else { return nil }

        self.init(percentAtFit: fitScale * screenScale * photoScale * 100)
    }

    /// range is the zoom a pinch may reach: from `minimumPercent` (or fit, if fit is already
    /// below it) up to `maximumPercent` (or fit, if fit is above it).
    var range: ClosedRange<Double> {
        let lower = min(Self.minimumPercent, percentAtFit) / percentAtFit
        let upper = max(Self.maximumPercent, percentAtFit) / percentAtFit

        return lower ... upper
    }

    /// percent(forZoom:) is the real percentage shown at `zoom`.
    func percent(forZoom zoom: Double) -> Double {
        zoom * percentAtFit
    }

    /// zoom(forPercent:) is the zoom that shows `percent`, clamped to `range`.
    func zoom(forPercent percent: Double) -> Double {
        clamped(percent / percentAtFit)
    }

    /// restingZoom(for:) is where a zoom that comes to rest settles: exactly the real 100 % when
    /// it is within `realPixelsSnap` of it, else `zoom` itself. At 100 % the canvas shows the photo's
    /// own pixels with nearest sampling, one texel per screen pixel, and a pinch that stops a hair
    /// off (99.7 %) would double or skip a column every few hundred pixels.
    func restingZoom(for zoom: Double) -> Double {
        let isNearRealPixels = abs(percent(forZoom: zoom) / 100 - 1) <= Self.realPixelsSnap

        return isNearRealPixels ? self.zoom(forPercent: 100) : zoom
    }

    /// zoomIn(from:) is the zoom of the next preset above `zoom`, or the top of the range. When fit
    /// lies outside the presets the range ends at fit, and the result is never below `zoom`.
    func zoomIn(from zoom: Double) -> Double {
        let percent = percent(forZoom: zoom) * (1 + Self.stepTolerance)
        let next    = Self.steps.first { $0 > percent }.map(self.zoom(forPercent:)) ?? range.upperBound

        return max(next, zoom)
    }

    /// zoomOut(from:) is the zoom of the next preset below `zoom`, or the bottom of the range. When
    /// fit lies outside the presets the range ends at fit, and the result is never above `zoom`.
    func zoomOut(from zoom: Double) -> Double {
        let percent  = percent(forZoom: zoom) * (1 - Self.stepTolerance)
        let previous = Self.steps.last { $0 < percent }.map(self.zoom(forPercent:)) ?? range.lowerBound

        return min(previous, zoom)
    }

    /// fillZoom(viewSize:imageSize:) is the zoom at which the photo covers the whole view: the
    /// larger of the two axis ratios over the smaller one (the fit), clamped to `range`.
    func fillZoom(
        viewSize : CGSize,
        imageSize: CGSize
    ) -> Double {
        guard viewSize.width > 0, viewSize.height > 0, imageSize.width > 0, imageSize.height > 0 else { return 1 }

        let widthRatio  = Double(viewSize.width)  / Double(imageSize.width)
        let heightRatio = Double(viewSize.height) / Double(imageSize.height)

        return clamped(max(widthRatio, heightRatio) / min(widthRatio, heightRatio))
    }

    /// landmarkTick(from:to:disarmed:) decides the pinch's tick: it is due when a zoom change passes
    /// fit or the real 100 %, in either direction (landing on a landmark counts as its upper side).
    ///
    /// Fingers resting on a landmark jitter across it by a hair on every frame, so the landmark
    /// that ticked comes back `disarmed`: it cannot tick again until the zoom has left the band of
    /// `rearmBand` around it. The caller keeps the returned `disarmed` and passes it in next time.
    func landmarkTick(
        from oldZoom: Double,
        to newZoom  : Double,
        disarmed    : Double?
    ) -> (ticks: Bool, disarmed: Double?) {
        let stillDisarmed = disarmed.flatMap { abs(newZoom / $0 - 1) <= Self.rearmBand ? $0 : nil }
        let crossed       = [1, 100 / percentAtFit].first { (oldZoom < $0) != (newZoom < $0) }

        guard let crossed, crossed != stillDisarmed else { return (false, stillDisarmed) }

        return (true, crossed)
    }

    /// indirectPinchFactor(for:) is the zoom factor of one trackpad pinch step of `scale`.
    static func indirectPinchFactor(for scale: Double) -> Double {
        pow(scale, indirectPinchExponent)
    }

    /// scrollZoomFactor(forTranslation:) is the zoom factor of one Cmd + scroll step of `points`
    /// vertical points of content travel, as the system delivers them (so the Natural Scrolling
    /// setting is already applied): content moving up zooms in, as in Photos, and down zooms out.
    /// It is exponential, so many small steps add up to one big step.
    static func scrollZoomFactor(forTranslation points: Double) -> Double {
        exp(-points * scrollZoomRate)
    }

    /// label(forPercent:) is the pill's number: whole from 10 % up, one decimal below it (6.3).
    static func label(forPercent percent: Double) -> String {
        let tenths = (percent * 10).rounded() / 10

        guard tenths < 10 else { return String(Int(percent.rounded())) }

        return String(format: "%.1f", tenths)
    }

    private func clamped(_ zoom: Double) -> Double {
        min(max(zoom, range.lowerBound), range.upperBound)
    }
}
