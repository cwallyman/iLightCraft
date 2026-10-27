//
//  NativeCropGuides.swift
//  iLightCraft
//

import UIKit

/// NativeCropGuides draws original geometric composition guides in the selected crop.
@MainActor enum NativeCropGuides {
    static func path(in rect: CGRect, kind: String, flipped: Bool) -> UIBezierPath {
        let path = UIBezierPath()
        guard rect.width > 0, rect.height > 0 else { return path }
        func line(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.addLine(to: b) }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        switch kind {
        case "none": break
        case "diagonal":
            line(point(0,0), point(1,1)); line(point(1,0), point(0,1))
        case "triangle":
            let a = point(0,0), b = point(1,1)
            line(a,b)
            let denominator = rect.width * rect.width + rect.height * rect.height
            for c in [point(1,0), point(0,1)] {
                let t = ((c.x-a.x) * rect.width + (c.y-a.y) * rect.height) / denominator
                line(c, CGPoint(x: a.x + t * rect.width, y: a.y + t * rect.height))
            }
        case "spiral":
            for step in 0...192 {
                let angle = CGFloat(step) * .pi / 48
                let radius = exp(-angle * log(1.61803398875) / (.pi / 2))
                let p = point(0.724 + radius * cos(angle + .pi) * 0.724, 0.553 + radius * sin(angle + .pi) * 0.553)
                if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        default:
            let positions: [CGFloat] = kind == "golden" ? [0.381966, 0.618034] : (kind == "grid" ? [0.2,0.4,0.6,0.8] : [1/3,2/3])
            for fraction in positions {
                line(point(fraction,0), point(fraction,1)); line(point(0,fraction), point(1,fraction))
            }
        }
        if flipped { path.apply(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * rect.midX, ty: 0)) }
        return path
    }
}
