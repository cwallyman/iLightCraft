//
//  HomeBackground.swift
//  Unveil
//

import SwiftUI

/// HomeBackground is the home's decorative backdrop: black, a soft purple glow, the "Unveil"
/// title centered in the upper half and five photo cards floating at different depths.
///
/// Depth drives everything about a card at once (scale, blur, shadow, dimming), so the five read
/// as layers of one scene. The drift is a set of repeating, autoreversing animations on each
/// card's offsets and tilt, with its own durations and start delay, so the body is evaluated
/// once per start or stop instead of once per frame. It runs only while `isMoving` (home shown,
/// panel not expanded) and never under Reduce Motion. Only the title is visible to VoiceOver.
struct HomeBackground: View {

    let isMoving: Bool

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State
    private var isDrifting: Bool = false

    var body: some View {
        GeometryReader { geometry in

            let upperHalf = CGSize(width: geometry.size.width, height: geometry.size.height / 2)

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

                ZStack {
                    ForEach(Self.cards) { card in
                        cardView(card, in: upperHalf)
                    }
                }
                .accessibilityHidden(true)

                Text("Unveil")
                    .font(.system(size: 88, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 24)
                    .accessibilityAddTraits(.isHeader)
                    .position(x: upperHalf.width / 2, y: upperHalf.height / 2)
            }
        }
        .ignoresSafeArea()
        .onChange(of: isMoving && !reduceMotion, initial: true) { _, shouldDrift in
            isDrifting = shouldDrift
        }
    }

    /// cardView lays one card out at rest and swings it between the two ends of its drift. The
    /// animations are scoped by `isDrifting`, so a layout change (a rotation) still moves at once.
    private func cardView(
        _ card : Card,
        in area: CGSize
    ) -> some View {
        let nearness = 1 - card.depth
        let swing    = isDrifting ? 1.0 : -1.0

        return Image(card.imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: card.width)
            .clipShape(.rect(cornerRadius: 18))
            .brightness(-card.depth * 0.25)
            .blur(radius: card.depth * 5)
            .shadow(
                color  : .black.opacity(0.35 + nearness * 0.3),
                radius : 8 + nearness * 26,
                y      : 6 + nearness * 18
            )
            .rotation3DEffect(
                .degrees(card.tilt + swing * 2),
                axis        : (x: 0.25, y: 1, z: 0),
                perspective : 0.6
            )
            .rotationEffect(.degrees(card.tilt * 0.3))
            .scaleEffect(0.6 + nearness * 0.4)
            .offset(x: swing * 14 * nearness)
            .animation(drift(seconds: card.swingSeconds, delay: card.startDelay), value: isDrifting)
            .offset(y: swing * 10 * nearness)
            .animation(drift(seconds: card.swingSeconds * 1.3, delay: card.startDelay), value: isDrifting)
            .position(x: area.width * card.position.x, y: area.height * card.position.y)
    }

    /// drift is the animation of one swing while the cards move. A stop uses a short ease out
    /// instead, which also replaces the repeating animation so nothing keeps running.
    private func drift(
        seconds: Double,
        delay  : Double
    ) -> Animation {
        guard isDrifting else { return .easeOut(duration: 0.6) }

        return .easeInOut(duration: seconds)
            .repeatForever(autoreverses: true)
            .delay(delay)
    }

    /// Card places one photo in the upper half: position as a fraction of that area, depth from
    /// 0 (nearest) to 1 (farthest), and its own swing duration and start delay so the five never
    /// move in step.
    private struct Card: Identifiable {

        let imageName   : String
        let position    : UnitPoint
        let width       : CGFloat
        let depth       : Double
        let tilt        : Double
        let swingSeconds: Double
        let startDelay  : Double

        var id: String { imageName }
    }

    private static let cards: [Card] = [
        Card(
            imageName    : "HomeCard-Z7-14bit-lossless-L",
            position     : UnitPoint(x: 0.30, y: 0.34),
            width        : 240,
            depth        : 0.85,
            tilt         : 10,
            swingSeconds : 28,
            startDelay   : 0.0
        ),
        Card(
            imageName    : "HomeCard-iPhone12Pro_IMG_1361",
            position     : UnitPoint(x: 0.71, y: 0.30),
            width        : 170,
            depth        : 0.70,
            tilt         : -12,
            swingSeconds : 24,
            startDelay   : 1.3
        ),
        Card(
            imageName    : "HomeCard-Canon_EOS_R5_RAW_ISO_100_nocrop_nodual",
            position     : UnitPoint(x: 0.52, y: 0.88),
            width        : 220,
            depth        : 0.95,
            tilt         : 4,
            swingSeconds : 26,
            startDelay   : 2.1
        ),
        Card(
            imageName    : "HomeCard-DSCF0267",
            position     : UnitPoint(x: 0.14, y: 0.62),
            width        : 300,
            depth        : 0.10,
            tilt         : 16,
            swingSeconds : 21,
            startDelay   : 3.4
        ),
        Card(
            imageName    : "HomeCard-ILCE-7M4_DSC06674_LossLess-Large",
            position     : UnitPoint(x: 0.86, y: 0.60),
            width        : 300,
            depth        : 0.00,
            tilt         : -18,
            swingSeconds : 22,
            startDelay   : 4.6
        ),
    ]
}
