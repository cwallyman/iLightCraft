//
//  HistogramPlot.swift
//  iLightCraft
//

import SwiftUI

/// HistogramPlot draws one frame of the histogram's glide (HistogramEasing's `levels`), filling its
/// frame, as HistogramView describes.
struct HistogramPlot: View {

    let levels: [Float]

    var body: some View {
        if LightCraftPanelStyle.isPad { smoothPlot } else { classicPlot }
    }

    /// smoothPlot is the iPad inspector's look: each channel is blurred across neighbouring bins and
    /// drawn as a curve, filled with a soft gradient and edged in its own colour.
    private var smoothPlot: some View {
        Canvas { context, size in
            guard levels.count == 4 * HistogramEasing.binCount else { return }

            let channels = (0 ..< 4).map { Self.smoothed(bins($0)) }
            let tallest = channels.prefix(3).map { $0.dropFirst().dropLast().max() ?? 0 }.max() ?? 0
            let peak = max(min(HistogramEasing.peak(of: levels), tallest), .leastNonzeroMagnitude)

            context.blendMode = .plusLighter
            for (channel, color) in Self.softColors.enumerated() {
                let points = Self.points(of: channels[channel][...], peak: peak, in: size)
                var area = Self.curve(through: points)
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.55), color.opacity(0.12)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(Self.curve(through: points), with: .color(color.opacity(0.9)), lineWidth: 1.5)
            }

            context.blendMode = .normal
            let luminance = Self.points(of: channels[3][...], peak: peak, in: size)
            context.stroke(Self.curve(through: luminance), with: .color(.white.opacity(0.55)), lineWidth: 1)
        }
    }

    private static let softColors = [
        Color(red: 1, green: 0.32, blue: 0.3),
        Color(red: 0.3, green: 0.85, blue: 0.4),
        Color(red: 0.3, green: 0.5, blue: 1),
    ]

    /// smoothed runs a small box blur three times (close to a Gaussian), then keeps every fourth bin
    /// so the curve has gentle control points instead of 256 jagged ones.
    private static func smoothed(_ bins: ArraySlice<Float>) -> [Float] {
        var values = Array(bins)
        let radius = 3
        for _ in 0 ..< 3 {
            values = values.indices.map { index in
                let low = max(0, index - radius), high = min(values.count - 1, index + radius)
                return values[low ... high].reduce(0, +) / Float(high - low + 1)
            }
        }
        return stride(from: 0, to: values.count, by: 4).map { values[$0] } + [values[values.count - 1]]
    }

    /// curve passes through every point with Catmull-Rom tangents, written as cubic Béziers.
    private static func curve(through points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for index in 1 ..< points.count {
                let p0 = points[max(index - 2, 0)], p1 = points[index - 1]
                let p2 = points[index], p3 = points[min(index + 1, points.count - 1)]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
        }
    }

    private var classicPlot: some View {
        Canvas { context, size in
            guard levels.count == 4 * HistogramEasing.binCount else { return }

            let peak = HistogramEasing.peak(of: levels)

            context.blendMode = .plusLighter

            for (channel, color) in Self.colors.enumerated() {
                context.fill(Self.area(of: bins(channel), peak: peak, in: size), with: .color(color.opacity(0.6)))
            }

            context.blendMode = .normal
            context.stroke(
                Self.outline(of: bins(3), peak: peak, in: size),
                with      : .color(.white.opacity(0.8)),
                lineWidth : 1
            )
        }
    }

    /// colors are the channels' pure primaries, not the system tints: only pure primaries add up to
    /// a neutral grey where all three overlap.
    private static let colors = [
        Color(red: 1, green: 0, blue: 0),
        Color(red: 0, green: 1, blue: 0),
        Color(red: 0, green: 0, blue: 1),
    ]

    /// bins are one channel's heights: 0 to 2 for red, green and blue, 3 for luminance.
    private func bins(_ channel: Int) -> ArraySlice<Float> {
        let start = channel * HistogramEasing.binCount

        return levels[start ..< start + HistogramEasing.binCount]
    }

    private static func points(of bins: ArraySlice<Float>, peak: Float, in size: CGSize) -> [CGPoint] {
        let step = size.width / CGFloat(max(bins.count - 1, 1))

        return bins.enumerated().map { index, level in
            let height = CGFloat(min(level / peak, 1)) * size.height
            return CGPoint(x: CGFloat(index) * step, y: size.height - height)
        }
    }

    private static func area(of bins: ArraySlice<Float>, peak: Float, in size: CGSize) -> Path {
        Path { path in
            // addLines would start a subpath of its own, closing the area along a diagonal.
            path.move(to: CGPoint(x: 0, y: size.height))
            points(of: bins, peak: peak, in: size).forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }

    private static func outline(of bins: ArraySlice<Float>, peak: Float, in size: CGSize) -> Path {
        Path { path in
            path.addLines(points(of: bins, peak: peak, in: size))
        }
    }
}
