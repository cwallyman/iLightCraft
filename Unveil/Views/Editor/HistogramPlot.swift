//
//  HistogramPlot.swift
//  Unveil
//

import SwiftUI

/// HistogramPlot draws one frame of the histogram's glide (HistogramEasing's `levels`), filling its
/// frame, as HistogramView describes.
struct HistogramPlot: View {

    let levels: [Float]

    var body: some View {
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
