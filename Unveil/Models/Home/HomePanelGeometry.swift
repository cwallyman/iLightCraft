//
//  HomePanelGeometry.swift
//  Unveil
//

import CoreGraphics

/// HomePanelGeometry is the arithmetic of the home panel's drag: where the panel sits for a
/// given finger translation, which detent a release settles on, and how fast the snap starts.
///
/// The panel is always laid out at full height and only moved by a vertical offset: 0 when
/// expanded, `travel` (half the available height) when collapsed. Moving it with a transform
/// instead of resizing it means the two embedded system browsers are laid out once per size
/// change, not once per finger move. Past either end the finger is followed with growing
/// resistance (the rubber band), capped at `rubberBandLimit` so the panel's hidden overscroll
/// padding always covers the gap.
nonisolated struct HomePanelGeometry: Equatable, Sendable {

    /// rubberBandLimit is the farthest the panel can be pulled past an end, in points.
    static let rubberBandLimit: CGFloat = 120

    /// projectionSeconds is how far ahead a release is projected along its velocity. Half a
    /// second is what UIScrollView's normal deceleration travels, so a short flick changes state.
    static let projectionSeconds: CGFloat = 0.5

    /// snapDuration is the perceptual duration of the snap spring, which has no bounce.
    static let snapDuration: Double = 0.4

    let travel: CGFloat

    /// restingOffset is the offset of a detent: 0 at full height, `travel` at half height.
    func restingOffset(isExpanded: Bool) -> CGFloat {
        isExpanded ? 0 : travel
    }

    /// offset is where the panel sits while a finger has moved it by `translation` (positive
    /// downward) from its detent: 1:1 inside the range, rubber-banded past either end.
    func offset(
        isExpanded : Bool,
        translation: CGFloat
    ) -> CGFloat {
        offset(from: restingOffset(isExpanded: isExpanded), translation: translation)
    }

    /// offset(from:translation:) is the same from any starting offset inside the range, for a
    /// drag that catches the panel while it is still snapping.
    func offset(
        from start : CGFloat,
        translation: CGFloat
    ) -> CGFloat {
        let raw = start + translation

        if raw < 0 {
            return -Self.rubberBanded(-raw)
        }
        if raw > travel {
            return travel + Self.rubberBanded(raw - travel)
        }
        return raw
    }

    /// settlesExpanded decides the detent of a release: the offset the throw would reach after
    /// `projectionSeconds` at the release velocity (points per second, positive downward), then
    /// whichever detent is nearer to it.
    func settlesExpanded(
        isExpanded : Bool,
        translation: CGFloat,
        velocity   : CGFloat
    ) -> Bool {
        settlesExpanded(
            released : offset(isExpanded: isExpanded, translation: translation),
            velocity : velocity
        )
    }

    /// settlesExpanded(released:velocity:) is the same from the offset the finger let go at.
    func settlesExpanded(
        released: CGFloat,
        velocity: CGFloat
    ) -> Bool {
        released + velocity * Self.projectionSeconds < travel / 2
    }

    /// snapVelocity is the release velocity in the unit SwiftUI's spring expects: the fraction of
    /// the remaining distance per second. It is capped at the spring's angular frequency, the
    /// largest start a critically damped spring takes without overshooting the detent, and a
    /// release moving away from the detent starts from rest: the finger's speed is not carried
    /// on past a rubber-banded end (or the panel would sail on, then swing back).
    func snapVelocity(
        from released: CGFloat,
        to target    : CGFloat,
        velocity     : CGFloat
    ) -> Double {
        let distance = Double(target - released)
        guard abs(distance) >= 1 else { return 0 }

        let frequency = 2 * Double.pi / Self.snapDuration

        return min(max(Double(velocity) / distance, 0), frequency)
    }

    /// rubberBanded maps a pull past an end to the displayed distance: about half the pull at
    /// first, then less and less, approaching `rubberBandLimit` but never reaching it.
    private static func rubberBanded(_ pull: CGFloat) -> CGFloat {
        let limit = rubberBandLimit

        return limit * pull / (pull + limit * 2)
    }
}
