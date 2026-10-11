//
//  HomeBackground.swift
//  Unveil
//

import SwiftUI

/// HomeBackground is the home's decorative backdrop: black, a soft purple glow, a few still
/// contour lines (HomeContours), the "Unveil" title centered in the upper half and five photo
/// cards floating at different depths.
///
/// The cards live in FloatingCardsView, whose Core Animation layers float on the render server,
/// so nothing here is evaluated per frame. They move only while `isMoving` (home shown, panel not
/// expanded) and the scene is active; becoming active again also restores the animations Core
/// Animation drops in the background. Under Reduce Motion the cards stand still. Only the title is
/// visible to VoiceOver.
struct HomeBackground: View {

    let isMoving: Bool

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.scenePhase)
    private var scenePhase

    var body: some View {
        GeometryReader { geometry in

            ZStack {

                Color.black

                RadialGradient(
                    colors      : [Color.accentColor.opacity(0.42), .clear],
                    center      : UnitPoint(x: 0.5, y: 0.22),
                    startRadius : 0,
                    endRadius   : max(geometry.size.width, geometry.size.height) * 0.6
                )

                RadialGradient(
                    colors      : [Color.accentColor.opacity(0.18), .clear],
                    center      : UnitPoint(x: 0.12, y: 0.9),
                    startRadius : 0,
                    endRadius   : geometry.size.width * 0.5
                )

                HomeContours()

                FloatingCards(
                    isMoving   : isMoving && scenePhase == .active,
                    isAnimated : !reduceMotion
                )
                .accessibilityHidden(true)

                Text("Unveil")
                    .font(.system(size: 88, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 24)
                    .accessibilityAddTraits(.isHeader)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 4)
            }
        }
        .ignoresSafeArea()
    }
}

/// FloatingCards hands the two motion flags to the native cards view; SwiftUI never sees a frame.
private struct FloatingCards: UIViewRepresentable {

    let isMoving  : Bool
    let isAnimated: Bool

    func makeUIView(context: Context) -> FloatingCardsView {
        FloatingCardsView()
    }

    func updateUIView(
        _ view : FloatingCardsView,
        context: Context
    ) {
        view.isAnimated = isAnimated
        view.isMoving   = isMoving
    }
}
