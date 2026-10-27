//
//  AdjustmentSlider.swift
//  iLightCraft
//

import SwiftUI

/// AdjustmentSlider is one develop control: its name and value on top, and below them a thin
/// themed track with a hollow handle.
///
/// It knows nothing about the engine. The value comes in as a plain number and the photo's own
/// default as `defaultValue`. Out go every new drag value (`onDragValue`), the drag edges
/// (`onEditingChanged`), every whole edit (`onCommit`: a value typed in, a VoiceOver step), every
/// stepper press (`onNudge`, a delta; the owner commits the burst once the presses stop) and a
/// reset (`onReset`, since temperature and tint go back to As Shot rather than to a number).
///
/// The row is Equatable on what it draws (kind, value, default), closures left out, so the panel's
/// `.equatable()` re-evaluates only the row whose value changed during a drag, not all eighteen.
///
/// The track is relative: a drag anywhere on it moves the thumb by the finger's motion, it never
/// jumps to the touch point, and a tap (even a sloppy one) or a vertical swipe does nothing.
/// Moving the finger vertically away from the track slows the motion down (`SliderSpeed`), and a
/// capsule names the band while it is not full speed. The fill follows `SliderFill`: centred
/// controls fill from the default.
///
/// Haptics: a tick when a drag crosses or lands on the default or reaches either end of the range
/// (HapticsAnchor, so a trackpad drag clicks too), a selection tick when it changes speed band and
/// at every stepper press, and a light impact on reset. A double tap on the name or on the track
/// resets; a tap on the value opens a ten-key popup.
///
/// For VoiceOver the row is one element: the name and the value are read once, a swipe up or
/// down moves the value by one step, and "Reset" resets it.
struct AdjustmentSlider: View {

    let kind            : DevelopAdjustmentKind
    let value           : Double
    let defaultValue    : Double
    let onDragValue     : (Double) -> Void
    let onEditingChanged: (Bool) -> Void
    let onCommit        : (Double) -> Void
    let onNudge         : (Double) -> Void
    let onReset         : () -> Void
    var isCompact       : Bool = false

    /// DragState is a drag in progress. `position` is the unrounded value the finger has reached,
    /// so slow motion below one step still accumulates; the binding gets it snapped to the step.
    private struct DragState {

        var position: Double
        var lastX   : CGFloat
        var speed   : SliderSpeed
    }

    private static let thumbSize   : CGFloat = 20
    private static let trackHeight : CGFloat = 4
    private static let dragSlop    : CGFloat = 8

    @Environment(\.isEnabled)
    private var isEnabled

    @GestureState
    private var isTrackTouched = false

    @State
    private var drag: DragState?

    /// isTrackSwipeIgnored is true for the rest of a track touch that started vertically: a page
    /// scroll that happens to begin on a track moves nothing.
    @State
    private var isTrackSwipeIgnored = false

    @State
    private var selectionTicks = 0

    /// alignmentTicks counts the default and range-end ticks; HapticsAnchor fires one per change,
    /// at `alignmentTickX` on the track.
    @State
    private var alignmentTicks = 0

    @State
    private var alignmentTickX: CGFloat = 0

    @State
    private var resets = 0

    @State
    private var isEntryShown = false

    #if DEBUG
    /// bodyRuns counts body evaluations per control in debug builds, so a test can check that a
    /// drag on one row leaves every other row alone.
    static var bodyRuns: [DevelopAdjustmentKind: Int] = [:]
    #endif

    var body: some View {
        #if DEBUG
        let _ = Self.bodyRuns[kind, default: 0] += 1
        #endif

        VStack(alignment: .leading, spacing: 2) {

            HStack(alignment: .firstTextBaseline) {

                Text(Self.title(of: kind))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: reset)

                LightCraftNumberButton(title: Self.title(of: kind), value: value, range: kind.range, step: kind.step,
                                       decimals: kind.step < 1 ? 2 : 0, display: formattedValue, isPresented: $isEntryShown, onCommit: onCommit)
                    .foregroundStyle(isAtDefault ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
            }
            .font(.system(size: 14))
            .foregroundStyle(isAtDefault ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)

            HStack(spacing: 0) {


                track

            }
        }
        .overlay(alignment: .top) { speedLabel }
        .animation(.easeOut(duration: 0.15), value: drag?.speed)
        .onChange(of: value) { oldValue, newValue in
            if let drag, ticks(from: oldValue, to: newValue) {
                alignmentTickX  = drag.lastX
                alignmentTicks += 1
            }
        }
        .onChange(of: isTrackTouched) { _, isTouched in
            if !isTouched {
                endDrag()
            }
        }
        .sensoryFeedback(.selection, trigger: selectionTicks)
        .sensoryFeedback(.impact(weight: .light), trigger: resets)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.title(of: kind))
        .accessibilityValue(formattedValue)
        .accessibilityAdjustableAction { direction in adjust(direction) }
        .accessibilityAction(named: "Reset", reset)
        .accessibilityAction(named: "Enter Value") { isEntryShown = true }
    }

    // MARK: - Track

    /// track draws the line, the fill, the default's tick (centred controls) and the thumb, inset
    /// by half a thumb so the thumb stays inside at both ends. The whole 32 pt band takes the drag.
    private var track: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - Self.thumbSize, 1)
            let fill   = SliderFill(
                value        : value,
                range        : kind.range,
                defaultValue : defaultValue
            )

            LightCraftSliderTrack(fraction: fill.thumb, controlID: kind.rawValue, isChanged: !isAtDefault)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(trackDrag(usableWidth: usable, height: proxy.size.height))
            .simultaneousGesture(TapGesture(count: 2).onEnded(reset))
            .background {
                HapticsAnchor(
                    ticks      : alignmentTicks,
                    location   : CGPoint(x: alignmentTickX, y: proxy.size.height / 2),
                    isDragging : drag != nil
                )
            }
        }
        .frame(height: 32)
    }

    /// trackDrag moves the value by the finger's horizontal motion, scaled by the speed band of
    /// its vertical distance from the track. The 8 pt slop is a dead zone: a tap's jitter never
    /// starts a drag, and motion counts from where the drag was recognized, so the thumb never
    /// jumps. A touch that starts mostly vertical is a swipe, not a drag, and moves nothing.
    private func trackDrag(usableWidth: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: Self.dragSlop)
            .updating($isTrackTouched) { _, isTouched, _ in isTouched = true }
            .onChanged { gesture in
                guard isEnabled, !isTrackSwipeIgnored else { return }

                if drag == nil, abs(gesture.translation.height) > abs(gesture.translation.width) {
                    isTrackSwipeIgnored = true
                    return
                }

                let speed = SliderSpeed(distance: gesture.location.y - height / 2)
                var state = drag ?? DragState(
                    position : value,
                    lastX    : gesture.location.x,
                    speed    : speed
                )

                if drag == nil {
                    onEditingChanged(true)
                } else if speed != state.speed {
                    selectionTicks += 1
                }

                let span  = kind.range.upperBound - kind.range.lowerBound
                let moved = Double(gesture.location.x - state.lastX) / Double(usableWidth) * span

                state.position = min(
                    max(state.position + moved * speed.factor, kind.range.lowerBound),
                    kind.range.upperBound
                )
                state.lastX = gesture.location.x
                state.speed = speed
                drag        = state

                let snapped = kind.snapped(state.position)
                if snapped != value {
                    onDragValue(snapped)
                }
            }
    }

    /// endDrag runs when the track's gesture ends or is cancelled (the gesture state resets in
    /// both cases), and only if a drag actually started.
    private func endDrag() {
        isTrackSwipeIgnored = false

        guard drag != nil else { return }

        drag = nil
        onEditingChanged(false)
    }

    @ViewBuilder
    private var speedLabel: some View {
        if let label = drag?.speed.label {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Stepper

    /// stepButton is the minus or plus of the stepper, disabled at the end of the range it moves
    /// toward. Holding it repeats (`buttonRepeatBehavior`), each repeat being one more press.
    private func stepButton(direction: Double) -> some View {
        let isAtLimit = direction < 0
            ? value <= kind.range.lowerBound
            : value >= kind.range.upperBound

        return Button {
            guard isEnabled else { return }

            selectionTicks += 1
            onNudge(direction * kind.step)
        } label: {
            Image(lightCraftIcon: direction < 0 ? "LightCraft-Minus" : "LightCraft-Plus")
                .font(.footnote.weight(.semibold))
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(.secondary)
        .disabled(isAtLimit)
    }

    // MARK: - Edits

    private func reset() {
        guard isEnabled else { return }

        resets += 1
        onReset()
    }

    /// adjust moves the value one step in the VoiceOver direction, as one whole edit. A disabled
    /// slider (no photo open) ignores it, as its touch gestures do.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard isEnabled else { return }

        switch direction {
            case .increment:
                onCommit(kind.snapped(value + kind.step))

            case .decrement:
                onCommit(kind.snapped(value - kind.step))

            @unknown default:
                return
        }
    }

    /// ticks(from:to:) is true when a drag's value change deserves a selection tick: it crosses or
    /// lands on the default, or it reaches either end of the range.
    private func ticks(from oldValue: Double, to newValue: Double) -> Bool {
        let before = oldValue - defaultValue
        let after  = newValue - defaultValue

        let crossesDefault = before * after < 0 || (after == 0 && before != 0)
        let reachesEnd     = newValue != oldValue
            && (newValue == kind.range.lowerBound || newValue == kind.range.upperBound)

        return crossesDefault || reachesEnd
    }

    // MARK: - Text

    private var isAtDefault: Bool { !LightCraftPanelStyle.isChanged(value, from: defaultValue) }

    private var defaultFraction: Double { SliderFill.fraction(of: defaultValue, in: kind.range) }

    /// formattedValue shows exposure in EV with a sign and two decimals, temperature in kelvin,
    /// and every other control as an integer, signed when its range goes below zero.
    private var formattedValue: String {
        let number = value

        switch kind {
            case .exposure:
                let text = number.formatted(
                    .number
                        .precision(.fractionLength(2))
                        .sign(strategy: .always(includingZero: false))
                )
                return "\(text) EV"

            case .temperature:
                return "\(number.formatted(.number.precision(.fractionLength(0)).grouping(.never))) K"

            default:
                let sign: NumberFormatStyleConfiguration.SignDisplayStrategy = kind.range.lowerBound < 0
                    ? .always(includingZero: false)
                    : .automatic
                return number.formatted(.number.precision(.fractionLength(0)).sign(strategy: sign))
        }
    }

    /// title(of:) is the control's name in the panel and in VoiceOver.
    private static func title(of kind: DevelopAdjustmentKind) -> String {
        switch kind {
            case .redHue, .orangeHue, .yellowHue, .greenHue, .aquaHue, .blueHue, .purpleHue, .magentaHue: "Hue"
            case .redSaturation, .orangeSaturation, .yellowSaturation, .greenSaturation, .aquaSaturation, .blueSaturation, .purpleSaturation, .magentaSaturation: "Saturation"
            case .redLuminance, .orangeLuminance, .yellowLuminance, .greenLuminance, .aquaLuminance, .blueLuminance, .purpleLuminance, .magentaLuminance: "Luminance"
            case .exposure:       "Exposure"
            case .contrast:       "Contrast"
            case .highlights:     "Highlights"
            case .shadows:        "Shadows"
            case .whites:         "Whites"
            case .blacks:         "Blacks"
            case .temperature:    "Temperature"
            case .tint:           "Tint"
            case .vibrance:       "Vibrance"
            case .saturation:     "Saturation"
            case .texture:        "Texture"
            case .clarity:        "Clarity"
            case .dehaze:         "Dehaze"
            case .sharpening:     "Sharpening"
            case .noiseReduction: "Noise Reduction"
            case .colorNoise:     "Color Noise Reduction"
            case .vignette:       "Vignette"
            case .grain:          "Grain"
        }
    }
}

extension AdjustmentSlider: Equatable {

    /// Two rows are equal when they draw the same. The closures are left out: the panel makes new
    /// ones on every pass, with the same behavior, and comparing them would never say equal.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.defaultValue == rhs.defaultValue && lhs.isCompact == rhs.isCompact
    }
}
