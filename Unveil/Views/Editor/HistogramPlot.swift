//
//  HistogramPlot.swift
//  Unveil
//

import SwiftUI

/// HistogramPlot draws one histogram, filling its frame, as HistogramView describes.
struct HistogramPlot: View {

    let histogram: FrameHistogram

    var body: some View {
        Canvas { context, size in
            let peak = Self.peak(of: histogram)

            context.blendMode = .plusLighter

            for (bins, color) in Self.channels(of: histogram) {
                context.fill(Self.area(of: bins, peak: peak, in: size), with: .color(color.opacity(0.6)))
            }

            context.blendMode = .normal
            context.stroke(
                Self.outline(of: histogram.luma, peak: peak, in: size),
                with      : .color(.white.opacity(0.8)),
                lineWidth : 1
            )
        }
    }

    /// channels pairs each channel with its pure primary, not the system tints: only pure primaries
    /// add up to a neutral grey where all three overlap.
    private static func channels(of histogram: FrameHistogram) -> [([UInt32], Color)] {
        [
            (histogram.red, Color(red: 1, green: 0, blue: 0)),
            (histogram.green, Color(red: 0, green: 1, blue: 0)),
            (histogram.blue, Color(red: 0, green: 0, blue: 1)),
        ]
    }

    /// peak is the square root of the tallest bin of any channel, ends excluded (see HistogramView).
    private static func peak(of histogram: FrameHistogram) -> Double {
        let inner = [histogram.red, histogram.green, histogram.blue, histogram.luma].map {
            $0.dropFirst().dropLast().max() ?? 0
        }

        return max(Double(inner.max() ?? 0).squareRoot(), 1)
    }

    private static func points(of bins: [UInt32], peak: Double, in size: CGSize) -> [CGPoint] {
        let step = size.width / CGFloat(max(bins.count - 1, 1))

        return bins.enumerated().map { index, count in
            let height = min(Double(count).squareRoot() / peak, 1) * size.height
            return CGPoint(x: CGFloat(index) * step, y: size.height - height)
        }
    }

    private static func area(of bins: [UInt32], peak: Double, in size: CGSize) -> Path {
        Path { path in
            // addLines would start a subpath of its own, closing the area along a diagonal.
            path.move(to: CGPoint(x: 0, y: size.height))
            points(of: bins, peak: peak, in: size).forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }

    private static func outline(of bins: [UInt32], peak: Double, in size: CGSize) -> Path {
        Path { path in
            path.addLines(points(of: bins, peak: peak, in: size))
        }
    }
}
