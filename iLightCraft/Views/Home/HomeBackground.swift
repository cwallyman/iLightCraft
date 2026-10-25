//
//  HomeBackground.swift
//  iLightCraft
//

import SwiftUI

/// HomeBackground presents the winking lynx and iLightCraft name above the library browser.
/// The native logo layer floats without per-frame SwiftUI updates and respects Reduce Motion.
struct HomeBackground: View {

    let isMoving: Bool
    var panelTop: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.scenePhase)
    private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let top = max(geometry.safeAreaInsets.top, geometry.size.height > geometry.size.width ? 58 : 12)
            let bottom = (panelTop ?? geometry.size.height * 0.44) - 78
            let available = max(bottom - top, 40)
            let side = min(geometry.size.width * 0.44, available * 0.65, 240)
            let titleSize = min(geometry.size.width * 0.105, available * 0.16, 60)

            ZStack {
                Color.black

                RadialGradient(
                    colors      : [Color.accentColor.opacity(0.24), .clear],
                    center      : UnitPoint(x: 0.5, y: 0.22),
                    startRadius : 0,
                    endRadius   : max(geometry.size.width, geometry.size.height) * 0.5
                )

                RadialGradient(
                    colors      : [Color.accentColor.opacity(0.08), .clear],
                    center      : UnitPoint(x: 0.12, y: 0.9),
                    startRadius : 0,
                    endRadius   : geometry.size.width * 0.5
                )

                HomeContours()

                VStack(spacing: min(available * 0.07, 20)) {
                    FloatingLogo(
                        isMoving   : isMoving && scenePhase == .active,
                        isAnimated : !reduceMotion
                    )
                    .frame(width: side, height: side)
                    .accessibilityHidden(true)

                    Text("iLightCraft")
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
                .position(x: geometry.size.width / 2, y: top + available / 2)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// FloatingLogo hands visibility and accessibility flags to the render-server animation.
private struct FloatingLogo: UIViewRepresentable {

    let isMoving  : Bool
    let isAnimated: Bool

    func makeUIView(context: Context) -> FloatingLogoView {
        FloatingLogoView()
    }

    func updateUIView(_ view: FloatingLogoView, context: Context) {
        view.isAnimated = isAnimated
        view.isMoving = isMoving
    }
}
