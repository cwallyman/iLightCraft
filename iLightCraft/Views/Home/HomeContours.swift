//
//  HomeContours.swift
//  iLightCraft
//

import SwiftUI

/// HomeContours draws a few long, gently curved hairlines across the home's backdrop, like the
/// contour lines of a map, so the black behind the cards does not feel empty.
///
/// They are decoration only and never move. Each is a cubic curve laid out as fractions of the
/// view, stroked 1 to 1.5 pt in the accent color at 6 to 12 % opacity, fading to clear along
/// its length. The Canvas has no changing inputs, so it is drawn once per size change. They are
/// hidden from VoiceOver.
struct HomeContours: View {

    var body: some View {
        Canvas { context, size in
            for line in Self.lines {
                context.stroke(
                    line.path(in: size),
                    with      : .linearGradient(
                        Gradient(colors: [Color.accentColor.opacity(line.opacity), .clear]),
                        startPoint : line.point(line.start, in: size),
                        endPoint   : line.point(line.end, in: size)
                    ),
                    lineWidth : line.width
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Line is one contour: its ends and control points as fractions of the view, its width and
    /// its opacity at the visible end (the gradient runs from `start` to clear at `end`).
    private struct Line {

        let start   : CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end     : CGPoint
        let width   : CGFloat
        let opacity : Double

        func point(
            _ fraction: CGPoint,
            in size   : CGSize
        ) -> CGPoint {
            CGPoint(x: fraction.x * size.width, y: fraction.y * size.height)
        }

        func path(in size: CGSize) -> Path {
            var path = Path()
            path.move(to: point(start, in: size))
            path.addCurve(
                to       : point(end, in: size),
                control1 : point(control1, in: size),
                control2 : point(control2, in: size)
            )
            return path
        }
    }

    private static let lines: [Line] = [
        Line(
            start    : CGPoint(x: -0.05, y: 0.18),
            control1 : CGPoint(x: 0.25, y: 0.05),
            control2 : CGPoint(x: 0.55, y: 0.35),
            end      : CGPoint(x: 1.05, y: 0.15),
            width    : 1.2,
            opacity  : 0.10
        ),
        Line(
            start    : CGPoint(x: 1.05, y: 0.29),
            control1 : CGPoint(x: 0.60, y: 0.47),
            control2 : CGPoint(x: 0.30, y: 0.19),
            end      : CGPoint(x: -0.05, y: 0.31),
            width    : 1.0,
            opacity  : 0.07
        ),
        Line(
            start    : CGPoint(x: -0.05, y: 0.43),
            control1 : CGPoint(x: 0.35, y: 0.56),
            control2 : CGPoint(x: 0.65, y: 0.26),
            end      : CGPoint(x: 1.05, y: 0.41),
            width    : 1.5,
            opacity  : 0.12
        ),
        Line(
            start    : CGPoint(x: 1.05, y: 0.09),
            control1 : CGPoint(x: 0.70, y: 0.01),
            control2 : CGPoint(x: 0.40, y: 0.21),
            end      : CGPoint(x: -0.05, y: 0.07),
            width    : 1.0,
            opacity  : 0.06
        ),
        Line(
            start    : CGPoint(x: 1.05, y: 0.49),
            control1 : CGPoint(x: 0.70, y: 0.63),
            control2 : CGPoint(x: 0.25, y: 0.39),
            end      : CGPoint(x: -0.05, y: 0.53),
            width    : 1.2,
            opacity  : 0.09
        ),
        Line(
            start    : CGPoint(x: 0.08, y: -0.02),
            control1 : CGPoint(x: 0.30, y: 0.30),
            control2 : CGPoint(x: 0.80, y: 0.10),
            end      : CGPoint(x: 1.05, y: 0.36),
            width    : 1.0,
            opacity  : 0.08
        ),
    ]
}
