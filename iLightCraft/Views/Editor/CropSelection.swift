//
//  CropSelection.swift
//  iLightCraft
//

import SwiftUI

/// Normalized selection over the uncropped preview, with movable corners and a draggable interior.
struct CropSelection: View {

    @Binding
    var rectangle: CropSettings.Rectangle

    let imageSize: CGSize
    let ratio: CGFloat?

    @State
    private var start: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rect = CGRect(x: rectangle.x0 * size.width, y: rectangle.y0 * size.height,
                              width: (rectangle.x1 - rectangle.x0) * size.width,
                              height: (rectangle.y1 - rectangle.y0) * size.height)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(rect)
                }
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: rect.width, height: rect.height)
                    .overlay { Rectangle().stroke(.white, lineWidth: 1) }
                    .overlay {
                        Path { path in
                            for n in 1...2 {
                                let f = CGFloat(n) / 3
                                path.move(to: CGPoint(x: rect.width * f, y: 0))
                                path.addLine(to: CGPoint(x: rect.width * f, y: rect.height))
                                path.move(to: CGPoint(x: 0, y: rect.height * f))
                                path.addLine(to: CGPoint(x: rect.width, y: rect.height * f))
                            }
                        }
                        .stroke(.white.opacity(0.6), lineWidth: 0.5)
                    }
                    .position(x: rect.midX, y: rect.midY)
                    .gesture(drag(corner: nil, size: size))
                    .accessibilityLabel("Crop position")
                    .accessibilityHint("Drag to move the selected area")

                ForEach(0..<4) { corner in
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .position(x: corner % 2 == 0 ? rect.minX : rect.maxX,
                                  y: corner < 2 ? rect.minY : rect.maxY)
                        .gesture(drag(corner: corner, size: size))
                        .accessibilityLabel(["Top left", "Top right", "Bottom left", "Bottom right"][corner] + " crop corner")
                }
            }
        }
    }

    private func drag(corner: Int?, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let initial = start ?? rectangle.cgRect
                start = initial
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                if let corner {
                    resize(initial, corner: corner, dx: dx, dy: dy)
                } else {
                    let x = min(1 - initial.width, max(0, initial.minX + dx))
                    let y = min(1 - initial.height, max(0, initial.minY + dy))
                    rectangle = .init(CGRect(x: x, y: y, width: initial.width, height: initial.height))
                }
            }
            .onEnded { _ in start = nil }
    }

    private func resize(_ rect: CGRect, corner: Int, dx: CGFloat, dy: CGFloat) {
        let left = corner % 2 == 0
        let top = corner < 2
        let anchor = CGPoint(x: left ? rect.maxX : rect.minX, y: top ? rect.maxY : rect.minY)
        let x = min(1, max(0, (left ? rect.minX : rect.maxX) + dx))
        let y = min(1, max(0, (top ? rect.minY : rect.maxY) + dy))
        let maxWidth = left ? anchor.x : 1 - anchor.x
        let maxHeight = top ? anchor.y : 1 - anchor.y
        var width = min(maxWidth, max(0.03, left ? anchor.x - x : x - anchor.x))
        var height = min(maxHeight, max(0.03, top ? anchor.y - y : y - anchor.y))
        if let ratio, imageSize.width > 0, imageSize.height > 0 {
            let normalized = ratio * imageSize.height / imageSize.width
            width = min(width, maxHeight * normalized)
            height = width / normalized
        }
        rectangle = .init(CGRect(x: left ? anchor.x - width : anchor.x,
                                y: top ? anchor.y - height : anchor.y, width: width, height: height))
    }
}
