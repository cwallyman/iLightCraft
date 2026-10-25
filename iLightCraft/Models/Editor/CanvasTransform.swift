//
//  CanvasTransform.swift
//  iLightCraft
//

import CoreGraphics
import Foundation

/// CanvasTransform maps the image into the view: aspect fit at zoom 1, then zoom and pan.
///
/// It is a plain value, a pure function of the gesture state, so it carries only
/// the two numbers the Metal layer needs to place the image quad. Its layout is
/// two plain fields, so the redraw path reads it on every frame without cost.
/// It is not `@frozen`: the compiler rejects that attribute on an internal type.
///
/// The geometry, with a view of `w x h` points and an image of `iw x ih` pixels:
/// the fit scale is `s = min(w / iw, h / ih)`, so at zoom 1 the image is `iw*s`
/// by `ih*s` points and centered in the view. Zoom multiplies that size around
/// the view center, and `offset` then moves the center, in view points with y
/// DOWN (the UIKit convention). The quad is returned in NDC with y UP (the Metal
/// convention), so the vertical offset changes sign on the way out.
///
/// A gesture may leave the transform somewhere it should not rest: with the image
/// pulled past an edge, or pinched past the ends of the zoom range. That is on purpose,
/// it is the rubber band. `settled` is where it springs back to when the fingers lift.
/// Zoom below fit is allowed and stays; the range of a zoom comes from `ZoomScale`.
nonisolated struct CanvasTransform: Equatable, Sendable {

    // nonisolated: pure value math, callable from the engine thread and from tests,
    // while the project default would pin it to the main actor.

    /// minimumToggleZoom is the least a double tap zooms in: a photo no larger than the screen
    /// is at 100 % (or more) already at fit, and a double tap must still go somewhere.
    static let minimumToggleZoom = 2.0

    /// rubberBandStiffness sets how fast the resistance grows past an edge: the
    /// image moves half as far as the finger at the edge, and less the further it goes.
    private static let rubberBandStiffness = 4.0

    /// zoomOvershootLimit is the farthest a pinch stretches past either end of its range, as a
    /// factor of that end: 1.25 lets 3200 % reach 4000 % before it stops dead.
    private static let zoomOvershootLimit = 1.25

    /// 1 means aspect fit.
    var zoom  : Double = 1

    /// Displacement of the image center from the view center, in view points, y down.
    var offset: SIMD2<Double> = .zero

    /// isFit is true at aspect fit, within a rounding error of the animations.
    var isFit: Bool { abs(zoom - 1) < 0.001 }

    /// quad(viewSize:imageSize:) returns the NDC corners of the image rectangle.
    ///
    /// Half the displayed size in points is `iw*s*zoom / 2`; dividing by `w / 2`
    /// (half the view, which is 1 in NDC) gives the NDC half-extent. A degenerate
    /// view or image yields an empty quad instead of dividing by zero.
    func quad(viewSize: CGSize, imageSize: CGSize) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        guard let fitScale = Self.fitScale(viewSize: viewSize, imageSize: imageSize) else {
            return (.zero, .zero)
        }

        let halfViewWidth   = Double(viewSize.width)   / 2
        let halfViewHeight  = Double(viewSize.height)  / 2
        let halfImageWidth  = Double(imageSize.width)  * fitScale * zoom / 2
        let halfImageHeight = Double(imageSize.height) * fitScale * zoom / 2

        // Offset y is down in view points, NDC y is up: hence the minus on offset.y.
        let minimum = SIMD2<Double>(
            (-halfImageWidth  + offset.x) / halfViewWidth,
            (-halfImageHeight - offset.y) / halfViewHeight
        )
        let maximum = SIMD2<Double>(
            ( halfImageWidth  + offset.x) / halfViewWidth,
            ( halfImageHeight - offset.y) / halfViewHeight
        )

        return (SIMD2<Float>(minimum), SIMD2<Float>(maximum))
    }

    /// imagePoint(at:viewSize:imageSize:) is the inverse of `quad`: it returns the
    /// image pixel (origin top-left, y down) shown under a view point (y down).
    ///
    /// A view point sits `viewPoint - center - offset` points from the image
    /// center, and one image pixel spans `fitScale * zoom` points.
    func imagePoint(at viewPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        guard let fitScale = Self.fitScale(viewSize: viewSize, imageSize: imageSize) else { return .zero }

        let pointsPerPixel = fitScale * zoom
        let fromCenterX    = Double(viewPoint.x) - Double(viewSize.width)  / 2 - offset.x
        let fromCenterY    = Double(viewPoint.y) - Double(viewSize.height) / 2 - offset.y

        return CGPoint(
            x: fromCenterX / pointsPerPixel + Double(imageSize.width)  / 2,
            y: fromCenterY / pointsPerPixel + Double(imageSize.height) / 2
        )
    }

    /// photoScale(previewSize:photoSize:) is preview pixels per photo pixel: the preview's long edge
    /// over the photo's. A screen-to-preview ratio times it is the ratio to real photo pixels. It is
    /// 1 while either size is unknown, so the pill falls back to preview pixels.
    static func photoScale(previewSize: CGSize, photoSize: CGSize) -> Double {
        let previewLong = Double(max(previewSize.width, previewSize.height))
        let photoLong   = Double(max(photoSize.width, photoSize.height))

        guard previewLong > 0, photoLong > 0 else { return 1 }

        return previewLong / photoLong
    }

    /// pinch(by:around:range:viewSize:) multiplies the zoom by `factor`, keeping the image point
    /// under `point` (view points, y down) where it is.
    ///
    /// With `d` the point relative to the view center, the image point under it is
    /// `(d - offset) / (fitScale * zoom)`. Asking for the same point after the zoom
    /// changes by `ratio` gives `offset' = d - ratio * (d - offset)`. The fit scale
    /// cancels out, which is why no image size is needed. A non-finite or non-positive
    /// factor is ignored.
    ///
    /// Inside `range` the zoom follows the fingers. Past an end it is the rubber band of
    /// `pan`, in log space so that it feels the same at 5 % and at 3200 %: an outward step
    /// is damped by `0.5 / (1 + k * overshoot / ln 2)` and stops at `zoomOvershootLimit`,
    /// a step back in is never damped. `settled(viewSize:imageSize:range:around:)` brings
    /// the zoom back to the end when the fingers lift.
    mutating func pinch(
        by factor   : Double,
        around point: CGPoint,
        range       : ClosedRange<Double>,
        viewSize    : CGSize
    ) {
        guard factor.isFinite, factor > 0 else { return }

        let lower = log(range.lowerBound)
        let upper = log(range.upperBound)
        let step  = log(factor)

        // The part of the step that stays inside the range is free; only the rest is damped.
        let start     = log(zoom)
        let isInside  = start >= lower && start <= upper
        let freeStep  = isInside ? min(max(start + step, lower), upper) - start : 0
        let restStep  = step - freeStep
        let position  = start + freeStep
        let overshoot = max(position - upper, lower - position, 0)
        let isOutward = restStep > 0 ? position >= upper : position <= lower
        let damping   = isOutward ? 0.5 / (1 + Self.rubberBandStiffness * overshoot / log(2.0)) : 1
        let margin    = log(Self.zoomOvershootLimit)
        let newZoom   = exp(min(max(position + restStep * damping, lower - margin), upper + margin))

        let ratio      = newZoom / zoom
        let fromCenter = SIMD2<Double>(
            Double(point.x) - Double(viewSize.width)  / 2,
            Double(point.y) - Double(viewSize.height) / 2
        )

        offset = fromCenter - ratio * (fromCenter - offset)
        zoom   = newZoom
    }

    /// pan(by:viewSize:imageSize:) moves the image by a gesture translation, in view points.
    ///
    /// Inside the edges the image follows the finger. Past an edge, a move further out
    /// is damped by `0.5 / (1 + k * overshoot / viewSide)`, so the image lags more the
    /// further it is pulled: the rubber band. A move back in is never damped. Without
    /// a usable size there are no edges and the image just follows.
    mutating func pan(by translation: CGPoint, viewSize: CGSize, imageSize: CGSize) {
        let delta = SIMD2<Double>(Double(translation.x), Double(translation.y))

        guard let limits = offsetLimits(viewSize: viewSize, imageSize: imageSize) else {
            offset += delta
            return
        }

        let viewSides = SIMD2<Double>(Double(viewSize.width), Double(viewSize.height))

        for axis in 0 ..< 2 where delta[axis] != 0 {
            let edge = delta[axis] > 0 ? limits[axis] : -limits[axis]

            // The part of the step that stays inside the edges is free; only the rest is damped.
            let isInside  = abs(offset[axis]) < limits[axis]
            let freeStep  = isInside ? min(max(offset[axis] + delta[axis], -limits[axis]), limits[axis]) - offset[axis] : 0
            let restStep  = delta[axis] - freeStep
            let position  = offset[axis] + freeStep
            let overshoot = abs(position) - limits[axis]
            let isOutward = delta[axis] > 0 ? position >= edge : position <= edge
            let factor    = isOutward ? 0.5 / (1 + Self.rubberBandStiffness * overshoot / viewSides[axis]) : 1

            offset[axis] = position + restStep * factor
        }
    }

    /// settled(viewSize:imageSize:) is where the transform comes to rest: the same zoom
    /// with the image pushed back inside its edges (an axis smaller than the view,
    /// as when zoomed out below fit, is centered).
    func settled(viewSize: CGSize, imageSize: CGSize) -> CanvasTransform {
        var result = self

        if let limits = offsetLimits(viewSize: viewSize, imageSize: imageSize) {
            result.offset = offset.clamped(lowerBound: -limits, upperBound: limits)
        }

        return result
    }

    /// settled(viewSize:imageSize:range:around:) is the rest after a pinch: a zoom stretched past
    /// an end of `range` springs back to that end around `point` (the fingers' last centroid), so
    /// the image under them stays put, and then the image is pushed back inside its edges.
    func settled(
        viewSize    : CGSize,
        imageSize   : CGSize,
        range       : ClosedRange<Double>,
        around point: CGPoint
    ) -> CanvasTransform {
        var result = self

        result.pinch(
            by       : min(max(zoom, range.lowerBound), range.upperBound) / zoom,
            around   : point,
            range    : range,
            viewSize : viewSize
        )

        return result.settled(viewSize: viewSize, imageSize: imageSize)
    }

    /// toggledZoom(at:viewSize:imageSize:screenScale:photoScale:) is the double tap: from a
    /// zoomed in view it returns to fit; from fit (or below) it zooms in on `point` to the
    /// photo's real 100 %, or to `minimumToggleZoom` when that is closer to fit. `photoScale`
    /// is preview pixels per photo pixel (see `photoScale(previewSize:photoSize:)`).
    func toggledZoom(
        at point   : CGPoint,
        viewSize   : CGSize,
        imageSize  : CGSize,
        screenScale: Double,
        photoScale : Double
    ) -> CanvasTransform {
        guard zoom <= 1.001 else { return CanvasTransform() }

        guard let fitScale = Self.fitScale(viewSize: viewSize, imageSize: imageSize),
              screenScale > 0,
              photoScale  > 0
        else {
            return self
        }

        let actualPixels = 1 / (fitScale * screenScale * photoScale)
        let upperZoom    = ZoomScale(percentAtFit: fitScale * screenScale * photoScale * 100)?.range.upperBound ?? 1
        let targetZoom   = min(max(actualPixels, Self.minimumToggleZoom), upperZoom)
        var result       = CanvasTransform()

        result.pinch(by: targetZoom, around: point, range: 1 ... targetZoom, viewSize: viewSize)

        return result.settled(viewSize: viewSize, imageSize: imageSize)
    }

    /// reset() returns to aspect fit, centered.
    mutating func reset() {
        self = CanvasTransform()
    }

    /// fitScale(viewSize:imageSize:) is view points per image pixel at zoom 1, or
    /// nil when either size is degenerate.
    static func fitScale(viewSize: CGSize, imageSize: CGSize) -> Double? {
        guard viewSize.width   > 0,
              viewSize.height  > 0,
              imageSize.width  > 0,
              imageSize.height > 0
        else {
            return nil
        }

        return min(
            Double(viewSize.width)  / Double(imageSize.width),
            Double(viewSize.height) / Double(imageSize.height)
        )
    }

    /// offsetLimits is how far the image center may sit from the view center on each
    /// axis: half of the part of the image that overflows the view, zero on an axis
    /// where the image is smaller than the view (it stays centered there).
    private func offsetLimits(viewSize: CGSize, imageSize: CGSize) -> SIMD2<Double>? {
        guard let fitScale = Self.fitScale(viewSize: viewSize, imageSize: imageSize) else { return nil }

        let shown = SIMD2<Double>(Double(imageSize.width), Double(imageSize.height)) * fitScale * zoom
        let view  = SIMD2<Double>(Double(viewSize.width), Double(viewSize.height))

        return ((shown - view) / 2).replacing(with: 0, where: shown .< view)
    }
}
